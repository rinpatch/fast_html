defmodule Mix.Tasks.FastHtml.Bench do
  @moduledoc "Benchmarking task."

  use Mix.Task

  @input_dir "lib/mix/tasks/fast_html/html"

  def run(_) do
    Application.ensure_all_started(:fast_html)

    inputs =
      Enum.reduce(File.ls!(@input_dir), %{}, fn input_name, acc ->
        input = File.read!(Path.join(@input_dir, input_name))
        Map.put(acc, input_name, input)
      end)

    Benchee.run(
      %{
        "Decoding" => fn input -> :fast_html.decode(input) end
      },
      inputs: inputs,
      save: [path: "fast_html.bench"],
      load: "fast_html.bench"
    )
  end
end
