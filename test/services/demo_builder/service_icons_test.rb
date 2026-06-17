# test/services/demo_builder/service_icons_test.rb
require "test_helper"

class DemoBuilder::ServiceIconsTest < ActiveSupport::TestCase
  # ─── Mappatura keyword → icona (spec) ─────────────────────────────────────

  test "assegna l'icona corretta in base alle parole chiave della spec" do
    cases = {
      "Specialità di pesce di lago"      => :fish,
      "Carta dei vini e cantina"         => :wine,
      "Organizzazione eventi e cerimonie" => :calendar,
      "Taglieri di salumi e formaggi"    => :utensils,
      "Cucina tipica del territorio"     => :chef_hat,
      "Menu degustazione"                => :chef_hat,
      "Prodotti di stagione"             => :leaf
    }

    cases.each do |text, expected|
      assert_equal expected, DemoBuilder::ServiceIcons.icon_key_for(text),
                   "#{text.inspect} dovrebbe mappare a #{expected}"
    end
  end

  test "il matching è case-insensitive" do
    assert_equal :fish, DemoBuilder::ServiceIcons.icon_key_for("PESCE FRESCO")
  end

  test "ricade sull'icona neutra se nessuna keyword matcha" do
    assert_equal :default, DemoBuilder::ServiceIcons.icon_key_for("Servizio generico xyz")
  end

  test "vince la prima regola in ordine (salumi → utensils, non meat)" do
    assert_equal :utensils, DemoBuilder::ServiceIcons.icon_key_for("Salumi misti")
    assert_equal :meat,     DemoBuilder::ServiceIcons.icon_key_for("Grigliata di carne")
  end

  # ─── Output SVG inline ────────────────────────────────────────────────────

  test "icon_for restituisce un SVG inline con stroke currentColor e nessun CDN" do
    svg = DemoBuilder::ServiceIcons.icon_for("pesce")

    assert svg.start_with?("<svg"), "deve essere SVG inline"
    assert svg.include?('stroke="currentColor"'), "eredita il colore dal contenitore"
    refute svg.include?("http"), "nessun riferimento esterno/CDN"
  end

  test "icone diverse per servizi diversi (no icona unica ✦)" do
    keys = ["pesce", "vino", "menu", "eventi"].map { |s| DemoBuilder::ServiceIcons.icon_key_for(s) }
    assert_equal keys, keys.uniq, "ogni servizio diverso deve avere icona diversa"
    refute DemoBuilder::ServiceIcons.icon_for("pesce").include?("✦")
  end
end
