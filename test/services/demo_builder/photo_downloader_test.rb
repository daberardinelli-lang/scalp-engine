# test/services/demo_builder/photo_downloader_test.rb
require "test_helper"
require "tmpdir"

class DemoBuilder::PhotoDownloaderTest < ActiveSupport::TestCase
  setup do
    @tmp_dir = Dir.mktmpdir("webradar_photo_test_")

    @company = FactoryBot.create(:company,
                                 name:            "Pizzeria da Test",
                                 city:            "Roma",
                                 status:          "demo_built",
                                 maps_photo_urls: [
                                   "https://places.googleapis.com/v1/places/X/photos/A/media?key=secret",
                                   "https://places.googleapis.com/v1/places/X/photos/B/media?key=secret"
                                 ])

    @demo = FactoryBot.create(:demo, company: @company, subdomain: "pizzeria-test-rm-abc")
  end

  teardown do
    FileUtils.rm_rf(@tmp_dir)
  end

  test "scarica le foto su disco e restituisce i path relativi" do
    with_tmp_storage do
      fetcher = ->(_url) { "JPEGDATA" }
      result  = DemoBuilder::PhotoDownloader.call(demo: @demo, fetcher: fetcher)

      assert result.success?, result.errors.inspect
      assert_equal ["img/photo_1.jpg", "img/photo_2.jpg"], result.paths

      img_dir = File.join(@tmp_dir, @demo.subdomain, "img")
      assert File.exist?(File.join(img_dir, "photo_1.jpg"))
      assert File.exist?(File.join(img_dir, "photo_2.jpg"))
      assert_equal "JPEGDATA", File.binread(File.join(img_dir, "photo_1.jpg"))
    end
  end

  test "salta le foto che falliscono il download e raccoglie gli errori" do
    with_tmp_storage do
      fetcher = lambda do |url|
        raise "boom" if url.include?("photos/B")

        "OK"
      end
      result = DemoBuilder::PhotoDownloader.call(demo: @demo, fetcher: fetcher)

      assert_equal ["img/photo_1.jpg"], result.paths
      assert_equal 1, result.errors.size
      refute result.success?
    end
  end

  test "restituisce paths vuoti se la company non ha foto" do
    with_tmp_storage do
      @company.update_column(:maps_photo_urls, [])
      result = DemoBuilder::PhotoDownloader.call(demo: @demo, fetcher: ->(_u) { "X" })

      assert_empty result.paths
      assert result.success?
    end
  end

  test "limita il download a MAX_PHOTOS" do
    with_tmp_storage do
      urls = Array.new(8) { |i| "https://places.googleapis.com/v1/photos/#{i}/media?key=secret" }
      @company.update_column(:maps_photo_urls, urls)

      result = DemoBuilder::PhotoDownloader.call(demo: @demo, fetcher: ->(_u) { "X" })

      assert_equal DemoBuilder::PhotoDownloader::MAX_PHOTOS, result.paths.size
    end
  end

  private

  def with_tmp_storage
    original = ENV["DEMO_STORAGE_PATH"]
    ENV["DEMO_STORAGE_PATH"] = @tmp_dir
    yield
  ensure
    ENV["DEMO_STORAGE_PATH"] = original
  end
end
