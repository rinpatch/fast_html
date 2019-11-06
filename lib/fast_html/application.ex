defmodule FastHtml.Application do
  @moduledoc false

  use Application

  application = Mix.Project.config()[:app]

  defp random_sname, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

  defp sname, do: :"fasthtml_#{random_sname()}"

  def start(_type, _args) do
    import Supervisor.Spec

    unless Node.alive?() do
      Nodex.Distributed.up()
    end

    myhtml_worker = Path.join(:code.priv_dir(unquote(application)), "myhtml_worker")

    children = [
      worker(Nodex.Cnode, [
        %{exec_path: myhtml_worker, sname: sname()},
        [name: FastHtml.Cnode]
      ])
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: FastHtml.Supervisor)
  end
end
