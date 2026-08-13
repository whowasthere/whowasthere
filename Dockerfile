FROM elixir:1.20-alpine AS build
WORKDIR /app
RUN apk add --no-cache build-base git
ENV MIX_ENV=prod
COPY mix.exs mix.lock ./
COPY config config
RUN mix local.hex --force && mix local.rebar --force && mix deps.get --only prod
COPY priv priv
COPY lib lib
COPY assets assets
COPY README.md README.md
COPY LICENSE LICENSE
RUN mix compile && mix assets.deploy && mix release

FROM alpine:3.22
RUN apk add --no-cache libstdc++ ncurses-libs openssl wget
WORKDIR /app
RUN adduser -D -u 1000 app && mkdir -p /data && chown app:app /data
USER app
COPY --from=build --chown=app:app /app/_build/prod/rel/whowasthere ./
ENV PHX_SERVER=true DATABASE_PATH=/data/whowasthere.db PORT=4000
EXPOSE 4000
VOLUME /data
CMD ["bin/whowasthere", "start"]
