defmodule Gno.Manifest.TypeTest do
  use GnoCase

  doctest Gno.Manifest.Type

  test "custom manifest type" do
    assert CustomManifest.manifest(
             load_path: TestData.manifest("single_file.ttl"),
             manifest_id: RDF.bnode("manifest")
           ) ==
             {:ok,
              %CustomManifest{
                __id__: RDF.bnode("manifest"),
                foo: "bar",
                load_path: TestData.manifest("single_file.ttl"),
                graph:
                  Graph.new(
                    [
                      EX.Service
                      |> RDF.type(Gno.Service)
                      |> Gno.serviceStore(EX.Store)
                      |> Gno.serviceRepository(EX.Repository),
                      EX.Store
                      |> RDF.type(GnoA.Oxigraph),
                      EX.Repository
                      |> RDF.type(Gno.Repository)
                      |> Gno.repositoryDataset(EX.Dataset),
                      {EX.S1, EX.P1, EX.O1},
                      {EX.S2, EX.P2, EX.O2}
                    ],
                    prefixes: [gno: Gno, gnoa: GnoA]
                  ),
                service: %Gno.Service{
                  __id__: ~I<http://example.com/Service>,
                  store: %Gno.Store.Adapters.Oxigraph{__id__: ~I<http://example.com/Store>},
                  repository: %Gno.Repository{
                    __id__: ~I<http://example.com/Repository>,
                    dataset: %Gno.Dataset{__id__: ~I<http://example.com/Dataset>}
                  }
                }
              }}
  end
end
