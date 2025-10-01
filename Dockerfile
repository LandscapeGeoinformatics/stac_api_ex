FROM elixir:1.15-alpine

# Install build dependencies
RUN apk add --no-cache build-base git

# Setting up the working dir
WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=dev

# Copy mix.exs and mix.lock
COPY mix.exs mix.lock ./

RUN mix deps.get

COPY . .

# Compilation
RUN mix compile


EXPOSE 4000


CMD ["mix", "phx.server"]
