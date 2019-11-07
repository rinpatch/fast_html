defmodule FastHTML.Mixfile do
  use Mix.Project

  def project do
    [
      app: :fast_html,
      version: "0.9.2",
      elixir: "~> 1.5",
      deps: deps(),
      package: package(),
      compilers: [:fast_html_cnode_make] ++ Mix.compilers(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      name: "FastHTML",
      description: """
        A module to decode HTML into a tree,
        porting all properties of the underlying
        library myhtml, being fast and correct
        in regards to the html spec.

        Originally based on Myhtmlex.
      """,
      docs: docs()
    ]
  end

  def package do
    [
      maintainers: ["Ariadne Conill", "rinpatch"],
      licenses: ["GNU LGPL"],
      links: %{
        "GitLab" => "https://git.pleroma.social/pleroma/fast_html",
        "Issues" => "https://git.pleroma.social/pleroma/fast_html/issues",
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
      mod: {FastHtml.Application, []},
      # used to detect conflicts with other applications named processes
      registered: [FastHtml.Cnode, FastHtml.Supervisor]
    ]
  end

  defp deps do
    [
      # documentation helpers
      {:ex_doc, "~> 0.19", only: :dev},
      # benchmarking helpers
      {:benchee, "~> 1.0", only: :dev}
    ]
  end

  defp docs do
    [
      main: "fast_html"
    ]
  end
end

defmodule Mix.Tasks.Compile.FastHtmlCnodeMake do
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

    exit_code =
      if match?({:win32, _}, :os.type()) do
        IO.warn("Windows is not yet a target.")
        1
      else
        {result, exit_code} =
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
        exit_code
      end

    if exit_code == 0 do
      :ok
    else
      {:error,
       [
         %Mix.Task.Compiler.Diagnostic{
           compiler_name: "FastHTML Cnode",
           message: "Make exited with #{exit_code}",
           severity: :error,
           file: nil,
           position: nil
         }
       ]}
    end
  end

  def clean() do
    make_cmd = find_make()
    {result, _error_code} = System.cmd(make_cmd, ["clean"], stderr_to_stdout: true)
    Mix.shell().info(result)
    :ok
  end
end
