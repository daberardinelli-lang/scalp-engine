FactoryBot.define do
  factory :user do
    first_name { Faker::Name.first_name }
    last_name  { Faker::Name.last_name }
    email      { Faker::Internet.unique.email }
    password   { "password123" }
    role       { :operator }
  end

  factory :company do
    name             { Faker::Company.name }
    category         { Company::CATEGORIES.sample }
    address          { Faker::Address.street_address }
    city             { "Prato" }
    province         { "PO" }
    phone            { Faker::PhoneNumber.phone_number }
    google_place_id  { SecureRandom.hex(10) }
    maps_rating      { rand(3.5..5.0).round(1) }
    maps_reviews_count { rand(5..200) }
    has_website      { false }
    email            { Faker::Internet.email }
    email_status     { "found" }
    status           { "discovered" }
  end

  factory :demo do
    association :company
    subdomain   { Demo.slugify(company.name) + "-#{SecureRandom.hex(3)}" }
    deployed_at { Time.current }
    expires_at  { 30.days.from_now }
  end

  factory :lead do
    association :company
    association :demo
    outcome     { "pending" }
  end
end
