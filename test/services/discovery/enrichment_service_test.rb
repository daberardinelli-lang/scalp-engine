require "test_helper"

class Discovery::EnrichmentServiceTest < ActiveSupport::TestCase
  # ─── Stub helpers ────────────────────────────────────────────────────────

  # Costruisce un fake ReviewFetcher che ritorna risultati controllati
  def fake_review_fetcher(reviews: [], error: nil)
    result = Discovery::ReviewFetcherService::Result.new(reviews: reviews, error: error)
    Module.new do
      define_singleton_method(:call) { |**_| result }
    end
  end

  # Costruisce un fake EmailExtractor che ritorna risultati controllati
  def fake_email_extractor(email: nil, source: nil, status: "unknown")
    result = Discovery::EmailExtractorService::Result.new(
      email: email, source: source, status: status
    )
    Module.new do
      define_singleton_method(:call) { |**_| result }
    end
  end

  SAMPLE_REVIEWS = [
    { "author" => "Mario Rossi",    "rating" => 5, "text" => "Ottimo!",   "date" => "2024-01-15" },
    { "author" => "Giulia Bianchi", "rating" => 4, "text" => "Molto buono.", "date" => "2024-01-10" }
  ].freeze

  # ─── Setup ───────────────────────────────────────────────────────────────

  setup do
    @company = FactoryBot.create(:company,
                                 status:          "discovered",
                                 google_place_id: "ChIJ_TEST",
                                 email_status:    "unknown",
                                 email:           nil,
                                 reviews_data:    [])
  end

  # ─── Test: flusso completo ───────────────────────────────────────────────

  test "porta la company a status enriched salvando email e recensioni" do
    result = call_service(
      reviews:      SAMPLE_REVIEWS,
      email:        "info@ristorantetest.it",
      email_source: "paginegialle",
      email_status: "found"
    )

    assert result.success?,     "deve completare senza errori"
    assert result.email_found?, "deve aver trovato l'email"
    assert_equal 2, result.reviews_count

    @company.reload
    assert_equal "enriched",               @company.status
    assert_equal "info@ristorantetest.it", @company.email
    assert_equal "paginegialle",           @company.email_source
    assert_equal "found",                  @company.email_status
    assert_equal 2,                        @company.reviews_data.size
    assert_not_nil                         @company.enriched_at
  end

  test "avanza a enriched anche senza email trovata" do
    result = call_service(reviews: SAMPLE_REVIEWS, email_status: "unknown")

    assert result.success?
    refute result.email_found?

    @company.reload
    assert_equal "enriched", @company.status
    assert_nil @company.email
  end

  test "avanza a enriched anche senza recensioni" do
    result = call_service(
      reviews: [], email: "test@example.it", email_source: "facebook", email_status: "found"
    )

    assert result.success?
    assert_equal 0, result.reviews_count

    @company.reload
    assert_equal "enriched", @company.status
  end

  test "skip se la company ha fatto opt-out" do
    @company.update!(opted_out_at: Time.current)

    result = call_service
    refute result.success?
    assert_match "opt-out", result.errors.first
    assert_equal "discovered", @company.reload.status
  end

  test "skip se la company non ha google_place_id" do
    @company.update_column(:google_place_id, nil)

    result = call_service
    refute result.success?
    assert_match "google_place_id", result.errors.first
  end

  test "registra errore se review fetcher fallisce ma prosegue" do
    result = call_service(
      reviews_error: "API error",
      email: "ok@example.it", email_source: "paginegialle", email_status: "found"
    )

    # Il service continua e salva comunque l'email
    @company.reload
    assert_equal "enriched",     @company.status
    assert_equal "ok@example.it", @company.email
    assert_equal 1,               result.errors.size
    assert_match "ReviewFetcher", result.errors.first
  end

  # ─── Test: Company helpers ────────────────────────────────────────────────

  test "average_review_rating calcola la media" do
    @company.reviews_data = [
      { "rating" => 5 }, { "rating" => 3 }, { "rating" => 4 }
    ]
    assert_in_delta 4.0, @company.average_review_rating, 0.01
  end

  test "average_review_rating ritorna nil con recensioni vuote" do
    @company.reviews_data = []
    assert_nil @company.average_review_rating
  end

  test "best_reviews restituisce solo recensioni rating >= 4 con testo" do
    @company.reviews_data = [
      { "rating" => 5, "text" => "eccellente", "author" => "A", "date" => "2024-01-01" },
      { "rating" => 2, "text" => "pessimo",    "author" => "B", "date" => "2024-01-02" },
      { "rating" => 4, "text" => "buono",      "author" => "C", "date" => "2024-01-03" },
      { "rating" => 5, "text" => "",           "author" => "D", "date" => "2024-01-04" }  # testo vuoto → escluso
    ]

    best = @company.best_reviews
    assert_equal 2, best.size
    assert best.all? { |r| r["rating"].to_i >= 4 && r["text"].present? }
  end

  test "enriched? è false se status=discovered" do
    assert_equal false, @company.enriched?
  end

  test "enriched? è true se status=enriched" do
    @company.status = "enriched"
    assert @company.enriched?
  end

  private

  def call_service(reviews: [], reviews_error: nil,
                   email: nil, email_source: nil, email_status: "unknown")
    Discovery::EnrichmentService.call(
      company:         @company,
      review_fetcher:  fake_review_fetcher(reviews: reviews, error: reviews_error),
      email_extractor: fake_email_extractor(email: email, source: email_source, status: email_status)
    )
  end
end
