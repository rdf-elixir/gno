defmodule Gno.Manifest do
  use Gno.Manifest.Type
  use Grax.Schema

  schema Gno.Manifest < DCATR.Manifest do
    link service: DCATR.manifestService(), type: Gno.Service, required: true
  end

  @impl true
  def generator_template, do: Gno.Manifest.Generator.default_template_dir()

  @impl true
  def generate(project_dir, opts \\ []) do
    Gno.Manifest.Generator.generate(__MODULE__, project_dir, opts)
  end
end
