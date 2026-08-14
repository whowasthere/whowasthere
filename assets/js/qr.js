// Dependency-free QR encoder for the short Solana Pay transfer URLs used here.
// Version 7, error correction M: up to 122 UTF-8 bytes.

const VERSION = 7
const SIZE = 45
const DATA_CODEWORDS = 124
const BLOCKS = 4
const BLOCK_DATA_CODEWORDS = 31
const ECC_CODEWORDS = 18
const ALIGNMENT_POSITIONS = [6, 22, 38]

const appendBits = (bits, value, length) => {
  for (let i = length - 1; i >= 0; i--) bits.push(((value >>> i) & 1) !== 0)
}

const multiply = (x, y) => {
  let result = 0
  for (let i = 7; i >= 0; i--) {
    result = (result << 1) ^ ((result >>> 7) * 0x11d)
    result ^= ((y >>> i) & 1) * x
  }
  return result
}

const reedSolomonDivisor = degree => {
  const result = new Array(degree).fill(0)
  result[degree - 1] = 1
  let root = 1

  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < result.length; j++) {
      result[j] = multiply(result[j], root)
      if (j + 1 < result.length) result[j] ^= result[j + 1]
    }
    root = multiply(root, 2)
  }
  return result
}

const reedSolomonRemainder = (data, divisor) => {
  const result = new Array(divisor.length).fill(0)

  for (const byte of data) {
    const factor = byte ^ result.shift()
    result.push(0)
    for (let i = 0; i < result.length; i++) {
      result[i] ^= multiply(divisor[i], factor)
    }
  }
  return result
}

const encodeData = text => {
  const bytes = [...new TextEncoder().encode(text)]
  if (bytes.length > 122) throw new Error("Solana Pay URI is too long for the QR encoder")

  const bits = []
  appendBits(bits, 0x4, 4)
  appendBits(bits, bytes.length, 8)
  for (const byte of bytes) appendBits(bits, byte, 8)

  const capacity = DATA_CODEWORDS * 8
  appendBits(bits, 0, Math.min(4, capacity - bits.length))
  while (bits.length % 8 !== 0) bits.push(false)

  const data = []
  for (let i = 0; i < bits.length; i += 8) {
    let byte = 0
    for (let j = 0; j < 8; j++) byte = (byte << 1) | Number(bits[i + j])
    data.push(byte)
  }

  for (let pad = 0; data.length < DATA_CODEWORDS; pad++) {
    data.push(pad % 2 === 0 ? 0xec : 0x11)
  }

  const divisor = reedSolomonDivisor(ECC_CODEWORDS)
  const blocks = []
  const ecc = []

  for (let i = 0; i < BLOCKS; i++) {
    const block = data.slice(i * BLOCK_DATA_CODEWORDS, (i + 1) * BLOCK_DATA_CODEWORDS)
    blocks.push(block)
    ecc.push(reedSolomonRemainder(block, divisor))
  }

  const result = []
  for (let i = 0; i < BLOCK_DATA_CODEWORDS; i++) {
    for (const block of blocks) result.push(block[i])
  }
  for (let i = 0; i < ECC_CODEWORDS; i++) {
    for (const block of ecc) result.push(block[i])
  }
  return result
}

const makeMatrix = text => {
  const codewords = encodeData(text)
  const modules = Array.from({length: SIZE}, () => new Array(SIZE).fill(false))
  const isFunction = Array.from({length: SIZE}, () => new Array(SIZE).fill(false))

  const setFunction = (x, y, dark) => {
    if (x < 0 || x >= SIZE || y < 0 || y >= SIZE) return
    modules[y][x] = dark
    isFunction[y][x] = true
  }

  const drawFinder = (cx, cy) => {
    for (let dy = -4; dy <= 4; dy++) {
      for (let dx = -4; dx <= 4; dx++) {
        const distance = Math.max(Math.abs(dx), Math.abs(dy))
        setFunction(cx + dx, cy + dy, distance !== 2 && distance !== 4)
      }
    }
  }

  const drawAlignment = (cx, cy) => {
    for (let dy = -2; dy <= 2; dy++) {
      for (let dx = -2; dx <= 2; dx++) {
        setFunction(cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1)
      }
    }
  }

  for (let i = 0; i < SIZE; i++) {
    setFunction(6, i, i % 2 === 0)
    setFunction(i, 6, i % 2 === 0)
  }

  drawFinder(3, 3)
  drawFinder(SIZE - 4, 3)
  drawFinder(3, SIZE - 4)

  for (let row = 0; row < ALIGNMENT_POSITIONS.length; row++) {
    for (let col = 0; col < ALIGNMENT_POSITIONS.length; col++) {
      const overlapsFinder =
        (row === 0 && col === 0) ||
        (row === 0 && col === ALIGNMENT_POSITIONS.length - 1) ||
        (row === ALIGNMENT_POSITIONS.length - 1 && col === 0)

      if (!overlapsFinder) {
        drawAlignment(ALIGNMENT_POSITIONS[col], ALIGNMENT_POSITIONS[row])
      }
    }
  }

  let formatRemainder = 0
  for (let i = 0; i < 10; i++) {
    formatRemainder = (formatRemainder << 1) ^ ((formatRemainder >>> 9) * 0x537)
  }
  const formatBits = formatRemainder ^ 0x5412
  const formatBit = index => ((formatBits >>> index) & 1) !== 0

  for (let i = 0; i <= 5; i++) setFunction(8, i, formatBit(i))
  setFunction(8, 7, formatBit(6))
  setFunction(8, 8, formatBit(7))
  setFunction(7, 8, formatBit(8))
  for (let i = 9; i < 15; i++) setFunction(14 - i, 8, formatBit(i))
  for (let i = 0; i < 8; i++) setFunction(SIZE - 1 - i, 8, formatBit(i))
  for (let i = 8; i < 15; i++) setFunction(8, SIZE - 15 + i, formatBit(i))
  setFunction(8, SIZE - 8, true)

  let versionRemainder = VERSION
  for (let i = 0; i < 12; i++) {
    versionRemainder =
      (versionRemainder << 1) ^ ((versionRemainder >>> 11) * 0x1f25)
  }
  const versionBits = (VERSION << 12) | versionRemainder

  for (let i = 0; i < 18; i++) {
    const bit = ((versionBits >>> i) & 1) !== 0
    const a = SIZE - 11 + (i % 3)
    const b = Math.floor(i / 3)
    setFunction(a, b, bit)
    setFunction(b, a, bit)
  }

  let bitIndex = 0
  for (let right = SIZE - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5

    for (let vertical = 0; vertical < SIZE; vertical++) {
      const upward = ((right + 1) & 2) === 0
      const y = upward ? SIZE - 1 - vertical : vertical

      for (let offset = 0; offset < 2; offset++) {
        const x = right - offset
        if (isFunction[y][x]) continue

        const byte = codewords[bitIndex >>> 3]
        const dark = ((byte >>> (7 - (bitIndex & 7))) & 1) !== 0
        modules[y][x] = dark !== ((x + y) % 2 === 0)
        bitIndex++
      }
    }
  }

  if (bitIndex !== codewords.length * 8) throw new Error("QR matrix size mismatch")
  return modules
}

export const drawQr = (canvas, text) => {
  const matrix = makeMatrix(text)
  const quiet = 4
  const scale = 8
  const dimension = (SIZE + quiet * 2) * scale
  const context = canvas.getContext("2d")

  canvas.width = dimension
  canvas.height = dimension
  context.fillStyle = "#ffffff"
  context.fillRect(0, 0, dimension, dimension)
  context.fillStyle = "#10151d"

  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      if (matrix[y][x]) {
        context.fillRect((x + quiet) * scale, (y + quiet) * scale, scale, scale)
      }
    }
  }
}
