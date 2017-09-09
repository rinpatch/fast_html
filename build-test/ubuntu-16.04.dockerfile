FROM ubuntu:xenial

RUN mkdir myhtmlex
WORKDIR myhtmlex

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y curl \
  && curl -LO https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb \
  && dpkg -i erlang-solutions_1.0_all.deb \
  && apt-get update \
  && apt-get install -y \
    git \
    esl-erlang \
    elixir \
    build-essential \
  && mix local.hex --force \
  && echo 'LANG=en_US.UTF-8' > /etc/default/locale \
  && echo 'LANGUAGE=en_US' >> /etc/default/locale

COPY . ./

# Test build
RUN mix deps.get \
  && make \
  && mix test \
  && mix bench \
  && make clean

# Test that it works as a dependency
RUN cd .. \
  && mix new myhtmlex_pkg_test \
  && cd myhtmlex_pkg_test \
  && sed -i"" 's/^.*dep_from_hexpm.*$/      {:myhtmlex, path: "..\/myhtmlex"}/' mix.exs \
  && mix deps.get \
  && mix compile \
  && mix run -e 'IO.inspect Myhtmlex.decode("foo")'

