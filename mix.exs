defmodule Myhtmlex.Mixfile do
  use Mix.Project

  def project do
    [
      app: :myhtmlex,
      version: "0.2.1",
      elixir: "~> 1.5",
      deps: deps(),
      package: package(),
      compilers: [:myhtmlex_make] ++ Mix.compilers(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      name: "Myhtmlex",
      description: """
        A module to decode HTML into a tree,
        porting all properties of the underlying
        library myhtml, being fast and correct
        in regards to the html spec.
      """,
      docs: docs()
    ]
  end

  def package do
    [
      maintainers: ["Lukas Rieder"],
      licenses: ["GNU LGPL"],
      links: %{
        "Github" => "https://git.pleroma.social/pleroma/myhtmlex",
        "Issues" => "https://git.pleroma.social/pleroma/myhtmlex/issues",
        "MyHTML" => "https://github.com/lexborisov/myhtml"
      },
      files: [
        "lib",
        "c_src",
        "priv/.gitignore",
        "test",
        "Makefile",
        "mix.exs",
        "README.md",
        "LICENSE"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Myhtmlex.Safe, []},
      # used to detect conflicts with other applications named processes
      registered: [Myhtmlex.Safe.Cnode, Myhtmlex.Safe.Supervisor],
      env: [
        mode: Myhtmlex.Safe
      ]
    ]
  end

  defp deps do
    [
      # documentation helpers
      {:ex_doc, ">= 0.0.0", only: :dev},
      # benchmarking helpers
      {:benchfella, "~> 0.3.0", only: :dev},
      # cnode helpers
      {:nodex,
       git: "https://git.pleroma.social/pleroma/nodex",
       ref: "cb6730f943cfc6aad674c92161be23a8411f15d1"}
    ]
  end

  defp docs do
    [
      main: "Myhtmlex"
    ]
  end
end

defmodule Mix.Tasks.Compile.MyhtmlexMake do
  @artifacts [
    "priv/myhtml_worker"
  ]

  def find_make do
    _make_cmd =
      System.get_env("MAKE") ||
        case :os.type() do
          {:unix, :freebsd} -> "gmake"
          {:unix, :openbsd} -> "gmake"
          {:unix, :netbsd} -> "gmake"
          {:unix, :dragonfly} -> "gmake"
          _ -> "make"
        end
  end

  defp otp_version do
    :erlang.system_info(:otp_release)
    |> to_string()
    |> String.to_integer()
  end

  defp otp_22_or_newer? do
    otp_version() >= 22
  end

  def run(_) do
    make_cmd = find_make()

    if match?({:win32, _}, :os.type()) do
      IO.warn("Windows is not yet a target.")
      exit(1)
    else
      {result, _error_code} =
        System.cmd(
          make_cmd,
          @artifacts,
          stderr_to_stdout: true,
          env: [
            {"MIX_ENV", to_string(Mix.env())},
            {"OTP22_DEF", (otp_22_or_newer?() && "YES") || "NO"}
          ]
        )

      IO.binwrite(result)
    end

    :ok
  end

  def clean() do
    make_cmd = find_make()
    {result, _error_code} = System.cmd(make_cmd, ["clean"], stderr_to_stdout: true)
    Mix.shell().info(result)
    :ok
  end
end
