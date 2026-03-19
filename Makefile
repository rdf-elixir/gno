GNO_ONTOLOGY  = priv/vocabs/gno.ttl
GNOA_ONTOLOGY = priv/vocabs/gno_store_adapter.ttl

# Generated outputs
BUILD_DIR = _site

GNO_HTML  = $(BUILD_DIR)/index.html
GNOA_HTML = $(BUILD_DIR)/store/adapter/index.html

GNO_FORMATS  = $(BUILD_DIR)/gno.ttl $(BUILD_DIR)/gno.nt $(BUILD_DIR)/gno.rdf $(BUILD_DIR)/gno.jsonld
GNOA_FORMATS = $(BUILD_DIR)/store/adapter/gnoa.ttl $(BUILD_DIR)/store/adapter/gnoa.nt $(BUILD_DIR)/store/adapter/gnoa.rdf $(BUILD_DIR)/store/adapter/gnoa.jsonld

.PHONY: all validate clean

all: $(GNO_HTML) $(GNOA_HTML) $(GNO_FORMATS) $(GNOA_FORMATS)

validate:
	rapper -i turtle -c $(GNO_ONTOLOGY)
	rapper -i turtle -c $(GNOA_ONTOLOGY)

# gno term docs
$(GNO_HTML): $(GNO_ONTOLOGY)
	@mkdir -p $(dir $@)
	pylode $< -o $@ -p ontpub --css true

# gnoa term docs
$(GNOA_HTML): $(GNOA_ONTOLOGY)
	@mkdir -p $(dir $@)
	pylode $< -o $@ -p ontpub --css true

# gno format conversions
$(BUILD_DIR)/gno.ttl: $(GNO_ONTOLOGY)
	@mkdir -p $(dir $@)
	cp $< $@

$(BUILD_DIR)/gno.nt: $(GNO_ONTOLOGY)
	@mkdir -p $(dir $@)
	rapper -i turtle -o ntriples $< > $@

$(BUILD_DIR)/gno.rdf: $(GNO_ONTOLOGY)
	@mkdir -p $(dir $@)
	rapper -i turtle -o rdfxml $< > $@

$(BUILD_DIR)/gno.jsonld: $(GNO_ONTOLOGY)
	@mkdir -p $(dir $@)
	python3 -c "from rdflib import Graph; g = Graph(); g.parse('$<'); print(g.serialize(format='json-ld'))" > $@

# gnoa format conversions
$(BUILD_DIR)/store/adapter/gnoa.ttl: $(GNOA_ONTOLOGY)
	@mkdir -p $(dir $@)
	cp $< $@

$(BUILD_DIR)/store/adapter/gnoa.nt: $(GNOA_ONTOLOGY)
	@mkdir -p $(dir $@)
	rapper -i turtle -o ntriples $< > $@

$(BUILD_DIR)/store/adapter/gnoa.rdf: $(GNOA_ONTOLOGY)
	@mkdir -p $(dir $@)
	rapper -i turtle -o rdfxml $< > $@

$(BUILD_DIR)/store/adapter/gnoa.jsonld: $(GNOA_ONTOLOGY)
	@mkdir -p $(dir $@)
	python3 -c "from rdflib import Graph; g = Graph(); g.parse('$<'); print(g.serialize(format='json-ld'))" > $@

clean:
	rm -rf $(BUILD_DIR)
