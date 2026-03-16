defmodule Gno.Manifest do
  @moduledoc """
  RDF-based configuration for `Gno.Service`s.

  Extends `DCATR.Manifest` with a `Gno.Service` link. Manifest files are
  Turtle files loaded from a `DCATR.Manifest.LoadPath`. All files in the
  environment-specific subdirectory are loaded and merged into a single graph.

  Custom manifest types can be defined via `Gno.Manifest.Type`, and manifest
  files can be generated with `Gno.Manifest.Generator`.

  ## Application Configuration

  Gno's manifest system is configured through the `:dcatr` application:

      config :dcatr,
        env: Mix.env(),
        load_path: ["config/gno"],
        manifest_type: Gno.Manifest,
        manifest_base: "http://example.com/"

  - `:env` - the current environment, used to select the environment-specific
    subdirectory (e.g. `config/gno/dev/`, `config/gno/test/`)
  - `:load_path` - directory paths for manifest file discovery
    (see `DCATR.Manifest.LoadPath`)
  - `:manifest_type` - the manifest module to use (always `Gno.Manifest` for
    plain Gno, or a custom module implementing `Gno.Manifest.Type`)
  - `:manifest_base` - base URI for resolving relative URIs in manifest files

  Additionally, an HTTP adapter must be configured for `Tesla`:

      config :tesla, adapter: Tesla.Adapter.Hackney

  ## Directory Structure

  Manifest files are organized by environment:

      config/gno/
      ├── dev/
      │   ├── service.ttl
      │   ├── repository.ttl
      │   └── fuseki.ttl
      └── test/
          ├── service.ttl
          ├── repository.ttl
          └── oxigraph.ttl

  ## Loading

  The manifest and its components can be loaded programmatically:

      {:ok, manifest} = Gno.manifest()
      {:ok, service}  = Gno.service()
      {:ok, store}    = Gno.store()
  """

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
