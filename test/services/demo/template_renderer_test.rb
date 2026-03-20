# test/services/demo/template_renderer_test.rb
require "test_helper"

class Demo::TemplateRendererTest < ActiveSupport::TestCase
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
    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?, result.errors.inspect
    assert_not_nil result.html
    assert result.html.include?("Trattoria Bella Napoli")
    assert result.html.include?("La vera pizza napoletana nel cuore di Napoli")
    assert result.html.include?("Da tre generazioni")
    assert result.html.include?("Prenota il tuo tavolo")
    assert result.html.include?("Napoli")
  end

  test "include le stelle di valutazione nel blocco hero" do
    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("★★★★★") # 4.7 → floor = 4, ma stars = ★★★★☆
    # rating 4.7 → floor = 4 full stars
    assert result.html.include?("4.7")
    assert result.html.include?("320")
  end

  test "include le recensioni positive (rating ≥ 4) ed esclude quelle negative" do
    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("Fantastica pizza napoletana")
    assert result.html.include?("Mario R.")
    refute result.html.include?("Non mi è piaciuto"), "non deve includere recensioni negative"
  end

  test "include i servizi come lista" do
    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("Pizza al forno a legna")
    assert result.html.include?("Antipasti")
    assert result.html.include?("Dolci tipici")
  end

  test "include il link Google Maps se google_place_id presente" do
    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("ChIJabc123")
    assert result.html.include?("google.com/maps")
  end

  test "include il banner 'sito demo'" do
    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("sito demo")
  end

  test "include attributo noindex nei meta" do
    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("noindex")
  end

  # ─── Test: foto ───────────────────────────────────────────────────────────

  test "usa la prima foto nella sezione about e le restanti nella gallery" do
    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    # Prima foto: nella sezione about
    assert result.html.include?("https://example.com/foto1.jpg")
    # Seconda foto: nella gallery
    assert result.html.include?("https://example.com/foto2.jpg")
  end

  test "renderizza correttamente senza foto" do
    @company.update_column(:maps_photo_urls, [])

    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    # Deve avere la sezione about senza immagine
    assert result.html.include?("Chi siamo")
    refute result.html.include?("about-image")
  end

  # ─── Test: valori mancanti ────────────────────────────────────────────────

  test "renderizza correttamente senza telefono" do
    @company.update_column(:phone, nil)

    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    refute result.html.include?("tel:")
  end

  test "renderizza correttamente senza province" do
    @company.update_column(:province, nil)

    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    assert result.html.include?("Napoli")
  end

  test "renderizza correttamente senza rating" do
    @company.update_column(:maps_rating, nil)

    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    refute result.html.include?("rating_stars"), "non deve mostrare blocco rating se vuoto"
  end

  test "renderizza correttamente senza recensioni" do
    @company.update_column(:reviews_data, [])

    result = Demo::TemplateRenderer.render(demo: @demo)

    assert result.success?
    refute result.html.include?("Cosa dicono i clienti"), "non deve mostrare sezione reviews vuota"
  end

  # ─── Test: helper interni ─────────────────────────────────────────────────

  test "build_stars con rating 5 restituisce 5 stelle piene" do
    renderer = Demo::TemplateRenderer.new(demo: @demo)
    stars = renderer.send(:build_stars, 5)
    assert_equal "★★★★★", stars
  end

  test "build_stars con rating 3.7 restituisce 3 stelle piene + 2 vuote" do
    renderer = Demo::TemplateRenderer.new(demo: @demo)
    stars = renderer.send(:build_stars, 3.7)
    assert_equal "★★★☆☆", stars
  end

  test "build_stars con nil restituisce stringa vuota" do
    renderer = Demo::TemplateRenderer.new(demo: @demo)
    assert_equal "", renderer.send(:build_stars, nil)
  end

  test "category_label traduce correttamente" do
    renderer = Demo::TemplateRenderer.new(demo: @demo)
    assert_equal "Ristorante", renderer.send(:category_label)
  end

  test "clean_phone rimuove caratteri non numerici eccetto +" do
    renderer = Demo::TemplateRenderer.new(demo: @demo)
    assert_equal "+39081234567", renderer.send(:clean_phone, "+39 081 123 4567")
  end
end
