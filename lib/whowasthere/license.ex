defmodule WhoWasThere.License do
  @moduledoc false

  @path Path.expand("../../LICENSE", __DIR__)
  @external_resource @path
  @text File.read!(@path)

  def text, do: @text
end
