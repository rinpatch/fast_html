defmodule FastHtml.Mixfile do
  use Mix.Project

  def project do
    [
      app: :fast_html,
      version: "2.0.0",
      elixir: "~> 1.5",
      deps: deps(),
      package: package(),
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_env: make_env(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      name: "FastHtml",
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
        "GitLab" => "https://git.pleroma.social/pleroma/elixir-libraries/fast_html/",
        "Issues" => "https://git.pleroma.social/pleroma/elixir-libraries/fast_html/issues",
        "MyHTML" => "https://github.com/lexborisov/myhtml"
      },
      files:
        [
          "lib",
          "priv/.gitignore",
          "test",
          "Makefile",
          "mix.exs",
          "README.md",
          "LICENSE"
        ] ++
          Enum.reject(
            Path.wildcard("c_src/**/*"),
            fn path ->
              Path.extname(path) in [".so", ".a", ".o"] or
                String.starts_with?(Path.basename(path), ".") or File.dir?(path)
            end
          )
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
      {:benchee, "~> 1.0", only: :bench, optional: true},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:myhtmlex, "~> 0.2.0", only: :bench, runtime: false, optional: true},
      {:mochiweb, "~> 2.18", only: :bench, optional: true},
      {:html5ever,
       git: "https://github.com/rusterlium/html5ever_elixir.git", only: :bench, optional: true},
      {:nimble_pool, "~> 0.1"},
      {:elixir_make, "~> 0.4", runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end

  defp otp_version do
    :erlang.system_info(:otp_release)
    |> to_string()
    |> String.to_integer()
  end

  defp otp_22_or_newer? do
    otp_version() >= 22
  end

  defp make_env do
    %{
      "OTP22_DEF" =>
        if otp_22_or_newer?() do
          "YES"
        else
          "NO"
        end
    }
  end
end
