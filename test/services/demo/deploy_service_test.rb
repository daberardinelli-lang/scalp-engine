# test/services/demo/deploy_service_test.rb
require "test_helper"
require "tmpdir"

class Demo::DeployServiceTest < ActiveSupport::TestCase
  SAMPLE_HTML = "<!DOCTYPE html><html><body><h1>Test Demo</h1></body></html>".freeze

  setup do
    @tmp_dir = Dir.mktmpdir("webradar_demo_test_")

    @company = FactoryBot.create(:company,
                                 name:    "Bar Centrale",
                                 city:    "Firenze",
                                 status:  "demo_built")

    @demo = FactoryBot.create(:demo,
                              company:            @company,
                              subdomain:          "bar-centrale-fi-xyz",
                              generated_headline: "Il caffè più buono di Firenze",
                              generated_about:    "Dal 1960 nel cuore della città.",
                              deployed_at:        nil,
                              expires_at:         nil)
  end

  teardown do
    FileUtils.rm_rf(@tmp_dir)
  end

  # ─── Test: happy path ─────────────────────────────────────────────────────

  test "scrive il file HTML su disco e aggiorna il record Demo" do
    with_tmp_storage do
      result = Demo::DeployService.call(demo: @demo, html: SAMPLE_HTML)

      assert result.success?, result.errors.inspect
      assert File.exist?(result.html_path), "il file HTML deve esistere su disco"
      assert_equal SAMPLE_HTML, File.read(result.html_path)

      @demo.reload
      assert_not_nil @demo.deployed_at
      assert_not_nil @demo.expires_at
      assert_equal result.html_path, @demo.html_path
      assert @demo.expires_at > Time.current
    end
  end

  test "crea la directory se non esiste" do
    with_tmp_storage do
      dir = File.join(@tmp_dir, @demo.subdomain)
      refute Dir.exist?(dir), "la directory non deve esistere prima del deploy"

      result = Demo::DeployService.call(demo: @demo, html: SAMPLE_HTML)

      assert result.success?
      assert Dir.exist?(dir), "la directory deve essere creata"
    end
  end

  test "sovrascrive un deploy precedente" do
    with_tmp_storage do
      Demo::DeployService.call(demo: @demo, html: "<html>Versione 1</html>")
      result = Demo::DeployService.call(demo: @demo, html: "<html>Versione 2</html>")

      assert result.success?
      assert_equal "<html>Versione 2</html>", File.read(result.html_path)
    end
  end

  test "imposta expires_at a 90 giorni da ora" do
    with_tmp_storage do
      before = Time.current

      Demo::DeployService.call(demo: @demo, html: SAMPLE_HTML)
      @demo.reload

      expected_min = before + 89.days
      expected_max = before + 91.days
      assert @demo.expires_at.between?(expected_min, expected_max),
             "expires_at deve essere circa 90 giorni da ora"
    end
  end

  # ─── Test: errori di validazione ──────────────────────────────────────────

  test "fallisce se HTML è blank" do
    result = Demo::DeployService.call(demo: @demo, html: "")

    refute result.success?
    assert result.errors.any? { |e| e.include?("HTML") }
  end

  test "fallisce se HTML è nil" do
    result = Demo::DeployService.call(demo: @demo, html: nil)

    refute result.success?
    assert result.errors.any? { |e| e.include?("HTML") }
  end

  test "fallisce se il subdomain del demo è blank" do
    @demo.subdomain = ""
    result = Demo::DeployService.call(demo: @demo, html: SAMPLE_HTML)

    refute result.success?
    assert result.errors.any? { |e| e.include?("Demo") || e.include?("subdomain") }
  end

  # ─── Test: Demo#deployed? ─────────────────────────────────────────────────

  test "Demo#deployed? ritorna false prima del deploy" do
    refute @demo.deployed?
  end

  test "Demo#deployed? ritorna true dopo il deploy" do
    with_tmp_storage do
      Demo::DeployService.call(demo: @demo, html: SAMPLE_HTML)
      @demo.reload
      assert @demo.deployed?
    end
  end

  test "Demo#active? ritorna true dopo il deploy (non scaduto)" do
    with_tmp_storage do
      Demo::DeployService.call(demo: @demo, html: SAMPLE_HTML)
      @demo.reload
      assert @demo.active?
    end
  end

  private

  # Sovrascrive DEMO_STORAGE_PATH con la directory temporanea per i test
  def with_tmp_storage
    original = ENV["DEMO_STORAGE_PATH"]
    ENV["DEMO_STORAGE_PATH"] = @tmp_dir
    yield
  ensure
    ENV["DEMO_STORAGE_PATH"] = original
  end
end
