defmodule Gno.Manifest.LoaderTest do
  use GnoCase

  doctest Gno.Manifest.Loader

  alias Gno.Manifest.{Loader, LoadingError}
  alias RDF.Graph
  alias DCAT.NS.DCTerms

  describe "load_graph/1" do
    test "with no config files" do
      assert Loader.load_graph(Gno.Manifest, load_path: []) ==
               {:error, %LoadingError{reason: :missing}}

      assert Loader.load_graph(Gno.Manifest, load_path: TestData.manifest("empty")) ==
               {:error, %LoadingError{reason: :missing}}
    end

    test "with single valid config file" do
      assert Loader.load_graph(Gno.Manifest, load_path: TestData.manifest("single_file.ttl")) ==
               {:ok,
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
                    |> Gno.repositoryDataset(EX.Dataset)
                  ],
                  prefixes: [gno: Gno, gnoa: GnoA]
                )}
    end

    test "with base" do
      assert Loader.load_graph(Gno.Manifest,
               load_path: TestData.manifest("base_relative.ttl"),
               base: EX.__base__()
             ) ==
               {:ok,
                Graph.new(
                  [
                    EX.Service
                    |> RDF.type(Gno.Service)
                    |> Gno.serviceStore(EX.Store)
                    |> Gno.serviceRepository(EX.Repository),
                    EX.Store
                    |> RDF.type(GnoA.Fuseki),
                    EX.Repository
                    |> RDF.type(Gno.Repository)
                    |> Gno.repositoryDataset(EX.Dataset)
                  ],
                  prefixes: [gno: Gno, gnoa: GnoA]
                )}
    end

    test "with invalid RDF content" do
      invalid_file = TestData.manifest("invalid.ttl")

      assert {:error, %LoadingError{reason: "Turtle scanner error " <> _, file: ^invalid_file}} =
               Loader.load_graph(Gno.Manifest, load_path: invalid_file)
    end

    test "with flat directory structure" do
      assert Loader.load_graph(Gno.Manifest, load_path: TestData.manifest("flat_dir")) ==
               {:ok,
                Graph.new(
                  [
                    EX.Service
                    |> RDF.type(Gno.Service)
                    |> Gno.serviceStore(EX.Store)
                    |> Gno.serviceRepository(EX.Repository),
                    EX.Store
                    |> RDF.type(GnoA.Fuseki)
                    |> Gno.storeEndpointDataset("some-dataset"),
                    EX.Repository
                    |> RDF.type(Gno.Repository)
                    |> Gno.repositoryDataset(EX.Dataset),
                    EX.Dataset
                    |> RDF.type(Gno.Dataset)
                    |> DCTerms.title("test dataset"),
                    EX.Agent
                    |> RDF.type(FOAF.Agent)
                    |> FOAF.name("Max Mustermann")
                    |> FOAF.mbox(~I<mailto:max.mustermann@example.com>)
                  ],
                  prefixes: [gno: Gno, gnoa: GnoA, foaf: FOAF, dcterms: DCTerms]
                )}
    end

    test "with nested directory structure" do
      assert Loader.load_graph(Gno.Manifest, load_path: TestData.manifest("nested_dir")) ==
               {:ok,
                Graph.new(
                  [
                    EX.Agent
                    |> RDF.type(FOAF.Agent)
                    |> FOAF.name("Max Mustermann"),
                    EX.Service
                    |> RDF.type(Gno.Service)
                    |> Gno.serviceStore(EX.Store)
                    |> Gno.serviceRepository(EX.Repository),
                    EX.Store
                    |> RDF.type(GnoA.Fuseki),
                    EX.Repository
                    |> RDF.type(Gno.Repository)
                    |> Gno.repositoryDataset(EX.Dataset),
                    EX.Dataset
                    |> RDF.type(Gno.Dataset)
                    |> DCTerms.title("test dataset")
                  ],
                  prefixes: [gno: Gno, gnoa: GnoA, foaf: FOAF, dcterms: DCTerms]
                )}
    end

    test "with environment-specific configuration" do
      assert Loader.load_graph(Gno.Manifest,
               load_path: TestData.manifest("env_specific"),
               env: :test
             ) ==
               {:ok,
                Graph.new(
                  [
                    EX.Service
                    |> RDF.type(Gno.Service)
                    |> DCTerms.title("Example service")
                    |> Gno.serviceStore(EX.Store),
                    EX.Store
                    |> RDF.type(GnoA.Fuseki)
                    |> Gno.storeEndpointPort(3030),
                    EX.Repository
                    |> RDF.type(Gno.Repository)
                    |> Gno.repositoryDataset(EX.Dataset)
                    |> DCTerms.creator(EX.Agent)
                    |> DCTerms.title("test repository"),
                    EX.Dataset
                    |> RDF.type(Gno.Dataset)
                    |> DCTerms.title("test dataset"),
                    EX.Agent
                    |> RDF.type(FOAF.Agent)
                    |> FOAF.name("Max Mustermann")
                    |> FOAF.mbox(~I<mailto:max.mustermann.test@example.com>)
                  ],
                  prefixes: [gno: Gno, gnoa: GnoA, foaf: FOAF, dcterms: DCTerms]
                )}

      assert Loader.load_graph(Gno.Manifest,
               load_path: TestData.manifest("env_specific"),
               env: :dev
             ) ==
               {:ok,
                Graph.new(
                  [
                    EX.Service
                    |> RDF.type(Gno.Service)
                    |> DCTerms.title("Example service")
                    |> Gno.serviceStore(EX.Store),
                    EX.Store
                    |> RDF.type(GnoA.Oxigraph),
                    EX.Repository
                    |> RDF.type(Gno.Repository)
                    |> Gno.repositoryDataset(EX.Dataset)
                    |> DCTerms.creator(EX.Agent)
                    |> DCTerms.title("dev repository"),
                    EX.Dataset
                    |> RDF.type(Gno.Dataset)
                    |> DCTerms.title("dev dataset"),
                    EX.Agent
                    |> RDF.type(FOAF.Agent)
                    |> FOAF.name("Max Mustermann")
                    |> FOAF.mbox(~I<mailto:max.mustermann@example.com>)
                  ],
                  prefixes: [gno: Gno, gnoa: GnoA, foaf: FOAF, dcterms: DCTerms]
                )}
    end
  end

  describe "loading a commit operation configuration" do
    test "custom commit operation and middlewares" do
      load_path = [
        TestData.manifest("single_file.ttl"),
        TestData.manifest("commit_config/custom_commit_operation_with_middleware.ttl")
      ]

      assert {:ok,
              %Gno.Manifest{
                load_path: ^load_path,
                service: %Gno.Service{
                  commit_operation: %TestCommitOperation{
                    middlewares: [
                      %Gno.CommitLogger{log_level: "info", log_states: ["all"]},
                      %TestStateFlowMiddleware{label: "first"},
                      %TestStateFlowMiddleware{label: "second"}
                    ]
                  }
                }
              }} = Loader.load(Gno.Manifest, load_path: load_path)
    end

    test "custom commit operation as class" do
      load_path = [
        TestData.manifest("single_file.ttl"),
        TestData.manifest("commit_config/custom_commit_operation_as_class.ttl")
      ]

      assert {:ok,
              %Gno.Manifest{
                load_path: ^load_path,
                service: %Gno.Service{
                  commit_operation: %TestCommitOperation{}
                }
              }} = Loader.load(Gno.Manifest, load_path: load_path)
    end

    test "commit middleware as class" do
      load_path = [
        TestData.manifest("single_file.ttl"),
        TestData.manifest("commit_config/commit_operation_with_middleware_as_class.ttl")
      ]

      assert {:ok,
              %Gno.Manifest{
                load_path: ^load_path,
                service: %Gno.Service{
                  commit_operation: %Gno.CommitOperation{
                    middlewares: [
                      %TestStateFlowMiddleware{label: "default"},
                      %Gno.CommitLogger{log_level: "info"}
                    ]
                  }
                }
              }} = Loader.load(Gno.Manifest, load_path: load_path)
    end
  end
end
