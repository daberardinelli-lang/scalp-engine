# test/services/demo_builder/template_renderer_test.rb
require "test_helper"

class DemoBuilder::TemplateRendererTest < ActiveSupport::TestCase
  setup do
    @company = FactoryBot.create(:company,
                                 name:               "Trattoria Bella Napoli",
                                 city:               "Napoli",
                                 province:           "NA",
                                 phone:              "+39 081 123 4567",
                                 category:           "restaurant",
                                 maps_rating:        4.7,
                                 maps_reviews_count: 320,
                                 google_place_id:    "ChIJabc123",
                                 maps_photo_urls:    ["https://example.com/foto1.jpg", "https://example.com/foto2.jpg"],
                                 reviews_data:       [
                                   { "author" => "Mario R.", "rating" => 5, "text" => "Fantastica pizza napoletana! Torneremo sicuramente.", "date" => "2024-01" },
                                   { "author" => "Laura B.", "rating" => 4, "text" => "Ottimo servizio e buon cibo tradizionale.", "date" => "2024-02" },
                                   { "author" => "Negativo X.", "rating" => 2, "text" => "Non mi è piaciuto.", "date" => "2024-03" }
                                 ],
                                 status:             "demo_built")

    @demo = FactoryBot.create(:demo,
                              company:             @company,
                              subdomain:           "bella-napoli-na-abc123",
                              generated_headline:  "La vera pizza napoletana nel cuore di Napoli",
                              generated_about:     "Da tre generazioni portiamo in tavola la tradizione culinaria partenopea.",
                              generated_services:  JSON.generate(["Pizza al forno a legna", "Antipasti", "Dolci tipici"]),
                              generated_cta:       "Prenota il tuo tavolo")
  end

  # ─── Test: rendering base ─────────────────────────────────────────────────

  test "renderizza HTML valido con tutti i dati azienda" do
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?, result.errors.inspect
    assert_not_nil result.html
    assert result.html.include?("Trattoria Bella Napoli")
    assert result.html.include?("La vera pizza napoletana nel cuore di Napoli")
    assert result.html.include?("Da tre generazioni")
    assert result.html.include?("Prenota il tuo tavolo")
    assert result.html.include?("Napoli")
  end

  test "include le stelle di valutazione nel blocco hero" do
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("★★★★★") # 4.7 → floor = 4, ma stars = ★★★★☆
    # rating 4.7 → floor = 4 full stars
    assert result.html.include?("4.7")
    assert result.html.include?("320")
  end

  test "include le recensioni positive (rating ≥ 4) ed esclude quelle negative" do
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("Fantastica pizza napoletana")
    assert result.html.include?("Mario R.")
    refute result.html.include?("Non mi è piaciuto"), "non deve includere recensioni negative"
  end

  test "include i servizi come lista" do
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("Pizza al forno a legna")
    assert result.html.include?("Antipasti")
    assert result.html.include?("Dolci tipici")
  end

  test "usa services_title e services_intro generati, senza copy generico" do
    @demo.update!(generated_services_title: "La cucina del lago",
                  generated_services_intro: "Pesce di lago e vini umbri a Piediluco.")
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("La cucina del lago")
    assert result.html.include?("Pesce di lago e vini umbri a Piediluco.")
    refute result.html.include?("Cosa offriamo"), "niente titolo fisso"
    refute result.html.include?("Tutto quello che serve"), "niente sottotitolo generico"
  end

  test "fallback titolo 'I nostri servizi' e nessun sottotitolo se title/intro vuoti" do
    @demo.update!(generated_services_title: nil, generated_services_intro: nil)
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("I nostri servizi")
    refute result.html.include?("Tutto quello che serve")
  end

  test "mostra service-desc se presente e la omette se vuota" do
    @demo.update!(generated_services: JSON.generate([
      { "name" => "Pici fatti in casa", "desc" => "Pasta tirata a mano ogni giorno." },
      { "name" => "Banchetti",          "desc" => "" }
    ]))
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("Pasta tirata a mano ogni giorno.")
    assert result.html.include?('class="service-desc"')
    refute result.html.include?('<p class="service-desc"></p>'), "niente paragrafo desc vuoto"
  end

  test "renderizza una griglia di 6 servizi" do
    six = (1..6).map { |i| { "name" => "Servizio #{i}", "desc" => "Dettaglio concreto #{i}." } }
    @demo.update!(generated_services: JSON.generate(six))
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert_equal 6, result.html.scan('class="service-card').size
  end

  test "include il link Google Maps se google_place_id presente" do
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("ChIJabc123")
    assert result.html.include?("google.com/maps")
  end

  # ─── Test: sezione Contatti (full-bleed + scheda glass) ───────────────────

  test "contatti: mappa full-bleed + scheda glass quando place_id presente" do
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?('class="contact-stage'), "stage full-bleed"
    assert result.html.include?('class="contact-map-bg"'), "mappa di sfondo"
    assert result.html.include?("output=embed"), "embed key-free, niente Maps Embed API"
    refute result.html.include?("maps/embed/v1/place"), "niente Maps Embed API"
    assert result.html.include?('class="contact-card'), "scheda flottante"
    assert result.html.include?('class="contact-pill"'), "pill brand"
    assert result.html.include?("Vieni a trovarci"), "titolo editoriale"
    assert result.html.include?('href="tel:+390811234567"'), "telefono cliccabile"
    assert result.html.include?("wa.me/39"), "bottone WhatsApp (phone presente → wa url)"
    refute result.html.include?('class="contact-wrapper"'), "vecchio layout rimosso"
  end

  test "contatti: fallback centrato senza iframe se google_place_id vuoto" do
    @company.update_column(:google_place_id, nil)
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?, result.errors.inspect
    assert result.html.include?("contact-stage-nomap"), "stage senza mappa"
    assert result.html.include?("contact-card-center"), "scheda centrata"
    refute result.html.include?("<iframe"), "nessun iframe mappa"
    assert result.html.include?("Vieni a trovarci")
  end

  test "contatti: render ok senza telefono (niente tel: né pulsante chiama)" do
    @company.update_column(:phone, nil)
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?, result.errors.inspect
    refute result.html.include?("tel:"), "nessun link telefono"
    refute result.html.include?("Chiama ora"), "nessuna CTA chiama"
    refute result.html.include?("wa.me"), "niente WhatsApp senza telefono"
    assert result.html.include?('class="contact-card'), "la scheda è comunque renderizzata"
  end

  test "include il banner 'sito demo'" do
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("sito demo")
  end

  test "include attributo noindex nei meta" do
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("noindex")
  end

  # ─── Test: foto ───────────────────────────────────────────────────────────

  test "usa la prima foto come hero e la seconda nella sezione about" do
    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    # Prima foto: sfondo hero a tutta pagina
    assert result.html.include?("hero-photo")
    assert result.html.include?("background-image:url('https://example.com/foto1.jpg')")
    # Seconda foto: sezione "chi siamo"
    assert result.html.include?("https://example.com/foto2.jpg")
  end

  test "usa i path locali quando photo_paths è fornito, non gli URL Google" do
    result = DemoBuilder::TemplateRenderer.render(
      demo:        @demo,
      photo_paths: ["img/photo_1.jpg", "img/photo_2.jpg"]
    )

    assert result.success?, result.errors.inspect
    assert result.html.include?("img/photo_1.jpg")
    assert result.html.include?("img/photo_2.jpg")
    # La API key e gli URL Google non devono finire nell'HTML
    refute result.html.include?("example.com/foto1.jpg"), "non deve usare gli URL Google"
    refute result.html.include?("places.googleapis.com"), "non deve esporre il media endpoint Google"
  end

  test "con photo_paths vuoto nasconde la gallery e non usa URL Google" do
    result = DemoBuilder::TemplateRenderer.render(demo: @demo, photo_paths: [])

    assert result.success?
    refute result.html.include?("example.com/foto1.jpg"), "non deve ricadere sugli URL Google"
    refute result.html.include?("I nostri ambienti"), "gallery deve essere nascosta"
  end

  test "renderizza correttamente senza foto" do
    @company.update_column(:maps_photo_urls, [])

    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    # Deve avere la sezione about senza immagine
    assert result.html.include?("Chi siamo")
    refute result.html.include?("about-image-wrap\">"), "non deve avere il blocco immagine about"
  end

  # ─── Test: valori mancanti ────────────────────────────────────────────────

  test "renderizza correttamente senza telefono" do
    @company.update_column(:phone, nil)

    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    refute result.html.include?("tel:")
  end

  test "renderizza correttamente senza province" do
    @company.update_column(:province, nil)

    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("Napoli")
  end

  test "renderizza correttamente senza rating" do
    @company.update_column(:maps_rating, nil)

    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    refute result.html.include?("rating_stars"), "non deve mostrare blocco rating se vuoto"
  end

  test "renderizza correttamente senza recensioni" do
    @company.update_column(:reviews_data, [])

    result = DemoBuilder::TemplateRenderer.render(demo: @demo)

    assert result.success?
    refute result.html.include?("Cosa dicono i clienti"), "non deve mostrare sezione reviews vuota"
  end

  # ─── Test: helper interni ─────────────────────────────────────────────────

  test "build_stars con rating 5 restituisce 5 stelle piene" do
    renderer = DemoBuilder::TemplateRenderer.new(demo: @demo)
    stars = renderer.send(:build_stars, 5)
    assert_equal "★★★★★", stars
  end

  test "build_stars con rating 3.7 restituisce 3 stelle piene + 2 vuote" do
    renderer = DemoBuilder::TemplateRenderer.new(demo: @demo)
    stars = renderer.send(:build_stars, 3.7)
    assert_equal "★★★☆☆", stars
  end

  test "build_stars con nil restituisce stringa vuota" do
    renderer = DemoBuilder::TemplateRenderer.new(demo: @demo)
    assert_equal "", renderer.send(:build_stars, nil)
  end

  test "category_label traduce correttamente" do
    renderer = DemoBuilder::TemplateRenderer.new(demo: @demo)
    assert_equal "Ristorante", renderer.send(:category_label)
  end

  test "clean_phone rimuove caratteri non numerici eccetto +" do
    renderer = DemoBuilder::TemplateRenderer.new(demo: @demo)
    assert_equal "+390811234567", renderer.send(:clean_phone, "+39 081 123 4567")
  end
end
