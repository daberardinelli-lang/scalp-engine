require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  test "nome e categoria obbligatori" do
    company = Company.new
    assert_not company.valid?
    assert_includes company.errors[:name],     "can't be blank"
    assert_includes company.errors[:category], "is not included in the list"
  end

  test "categoria valida" do
    company = Company.new(name: "Test", category: "restaurant", status: "discovered")
    assert company.valid?
  end

  test "categoria non valida" do
    company = Company.new(name: "Test", category: "invalid_cat", status: "discovered")
    assert_not company.valid?
  end

  test "opted_out? restituisce true se opted_out_at presente" do
    company = Company.new(opted_out_at: Time.current)
    assert company.opted_out?
  end

  test "slugify genera slug corretto" do
    assert_equal "pizzeria-da-mario",     Demo.slugify("Pizzeria Da Mario")
    assert_equal "studio-legale-rossi",   Demo.slugify("Studio Legale Rossi")
    assert_equal "bar-e-cafe-bella-vita", Demo.slugify("Bar & Cafè Bella Vita")
  end
end
