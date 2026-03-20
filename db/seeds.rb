# db/seeds.rb
# Crea utente admin di default per sviluppo

if Rails.env.development?
  admin = User.find_or_create_by!(email: "admin@webradar.local") do |u|
    u.password              = "password123"
    u.password_confirmation = "password123"
    u.first_name            = "Admin"
    u.last_name             = "WebRadar"
    u.role                  = :admin
  end
  puts "Utente admin creato: #{admin.email} / password123"
end
