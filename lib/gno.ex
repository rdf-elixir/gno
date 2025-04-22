defmodule Gno do
  import RDF.Namespace
  act_as_namespace Gno.NS.Gno

  defdelegate manifest(opts \\ []), to: Gno.Manifest
  defdelegate manifest!(opts \\ []), to: Gno.Manifest

  defdelegate service(opts \\ []), to: Gno.Manifest
  defdelegate service!(opts \\ []), to: Gno.Manifest

  defdelegate store(opts \\ []), to: Gno.Manifest
  defdelegate store!(opts \\ []), to: Gno.Manifest

  defdelegate repository(opts \\ []), to: Gno.Manifest
  defdelegate repository!(opts \\ []), to: Gno.Manifest

  defdelegate dataset(opts \\ []), to: Gno.Manifest
  defdelegate dataset!(opts \\ []), to: Gno.Manifest
end
