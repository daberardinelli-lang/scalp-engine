# test/services/demo_builder/category_hero_scene_test.rb
require "test_helper"
require "tmpdir"

class DemoBuilder::CategoryHeroSceneTest < ActiveSupport::TestCase
  setup do
    @tmp  = Dir.mktmpdir("webradar_video_test_")
    @orig = ENV["DEMO_STORAGE_PATH"]
    ENV["DEMO_STORAGE_PATH"] = @tmp
  end

  teardown do
    ENV["DEMO_STORAGE_PATH"] = @orig
    FileUtils.rm_rf(@tmp)
  end

  # Crea una clip fittizia (no .mp4 reali nei test)
  def make_video(folder)
    dir = File.join(@tmp, "_assets", "video", folder)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "hero.mp4"), "")
  end

  def company(name:, category: "other")
    Company.new(name: name, category: category)
  end

  # ─── Match fine per keyword ───────────────────────────────────────────────

  test "match fine: 'Enoteca Bianchi' => enoteca" do
    assert_equal "enoteca",
                 DemoBuilder::CategoryHeroScene.match_keyword(company(name: "Enoteca Bianchi", category: "shop"))
  end

  test "folder_for usa il match fine quando la clip esiste" do
    make_video("enoteca")
    assert_equal "enoteca",
                 DemoBuilder::CategoryHeroScene.folder_for(company(name: "Enoteca Bianchi", category: "shop"))
  end

  # ─── Fallback sulla categoria larga ───────────────────────────────────────

  test "fallback categoria: restaurant => ristorante" do
    make_video("ristorante")
    assert_equal "ristorante",
                 DemoBuilder::CategoryHeroScene.folder_for(company(name: "Da Mario", category: "restaurant"))
  end

  # ─── Cartella scelta inesistente → default → nil ──────────────────────────

  test "clip della cartella scelta assente => usa default" do
    make_video("default")
    # "Pizzeria Napoli" → match pizzeria, ma manca pizzeria/hero.mp4 → default
    assert_equal "default",
                 DemoBuilder::CategoryHeroScene.folder_for(company(name: "Pizzeria Napoli", category: "restaurant"))
  end

  test "nessuna clip disponibile => nil (l'hero userà la foto Maps)" do
    assert_nil DemoBuilder::CategoryHeroScene.folder_for(company(name: "Pizzeria Napoli", category: "restaurant"))
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  test "video_url resta relativo a /_assets" do
    assert_equal "/_assets/video/enoteca/hero.mp4",
                 DemoBuilder::CategoryHeroScene.video_url("enoteca")
  end

  test "storage_base segue DEMO_STORAGE_PATH" do
    assert_equal @tmp, DemoBuilder::CategoryHeroScene.storage_base
  end
end
