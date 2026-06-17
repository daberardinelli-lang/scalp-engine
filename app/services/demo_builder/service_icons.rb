# app/services/demo_builder/service_icons.rb
#
# Assegna a ogni servizio un'icona SVG pertinente in base alle parole chiave
# presenti nel testo del servizio. Sostituisce l'icona "✦" identica su ogni card,
# che è uno dei segnali più forti di "template generato da AI".
#
# Le icone sono SVG inline (set Lucide, MIT) con stroke="currentColor": ereditano
# il colore dal contenitore .service-icon. Nessuna dipendenza esterna, nessun CDN.
#
# Uso:
#   DemoBuilder::ServiceIcons.icon_for("Specialità di pesce di lago")  # => "<svg …fish…>"
#
module DemoBuilder
  module ServiceIcons
    # Regole keyword → icona, valutate in ordine: vince la PRIMA che matcha.
    # Le regole più specifiche stanno in alto. Match per sottostringa (downcase),
    # così "pesce"/"pescato" o "vini"/"vino" funzionano senza elencare tutte le forme.
    RULES = [
      [%w[pizz],                                                            :pizza],
      [%w[pesce pescat frutti\ di\ mare crostace mare lago sushi],          :fish],
      [%w[vino vini cantina enotec doc docg bottigl sommelier],             :wine],
      [%w[caff colazione cappuccino aperitiv brioche],                      :coffee],
      [%w[dolc pasticc tort gelat dessert crostata biscott],                :cake],
      [%w[formagg salum tagliere taglier affettat latticin],                :utensils],
      [%w[carne grigl brace bistecc arrosto macell],                        :meat],
      [%w[menu cucina chef],                                                :chef_hat],
      [%w[stagion km\ zero chilometro\ zero biologic vegetar vegan orto local natural genuin], :leaf],
      [%w[event cena cene banchett catering riceviment cerimoni festa feste compleann], :calendar],
      [%w[grupp comitiv tavolat],                                           :users],
      [%w[taglio capell parrucch barbier piega messa\ in\ piega],           :scissors],
      [%w[estetic bellezz benesser massagg spa trattament manicure unghie ricostruz], :sparkles],
      [%w[ripar manutenz installaz idraul elettr impiant caldaia condizion],:wrench],
      [%w[artigian lavoraz fatto\ a\ mano handmade su\ misura sartori falegnam], :hammer],
      [%w[ristruttur edil muratura cartongesso paviment imbianc],           :home_tool],
      [%w[immobil affitt appartament casa abitaz villa],                    :home],
      [%w[consulenz legal fiscal commercialist contabil avvocat notaio assicur perizia], :briefcase],
      [%w[negozio abbigliam accessori boutique shop articol],               :shopping_bag],
      [%w[conseg domicili spedizion traspport asporto delivery],            :truck],
      [%w[cura salute assistenz medic fisioterap dentist clinica terapia],  :heart],
      [%w[cucina piatt cibo gastronom ristoraz tradiziona specialit antipast prim second contorn], :chef_hat]
    ].freeze

    # Inner-markup di ogni icona (path Lucide). Il wrapper <svg> è aggiunto da #icon_for.
    PATHS = {
      pizza:        '<path d="M15 11h.01"/><path d="M11 15h.01"/><path d="M16 16h.01"/><path d="m2 16 20 6-6-20A20 20 0 0 0 2 16"/><path d="M5.71 17.11a17.04 17.04 0 0 1 11.4-11.4"/>',
      fish:         '<path d="M6.5 12c.94-3.46 4.94-6 8.5-6 3.56 0 6.06 2.54 7 6-.94 3.47-3.44 6-7 6s-7.56-2.53-8.5-6Z"/><path d="M18 12v.5"/><path d="M16 17.93a9.77 9.77 0 0 1 0-11.86"/><path d="M7 10.67C7 8 5.58 5.97 2.73 5.5c-1 1.5-1 5 .23 6.5-1.24 1.5-1.24 5-.23 6.5C5.58 18.03 7 16 7 13.33"/><path d="m10.46 7.26.34 1.4M16 17.93l-.23 1.4"/>',
      wine:         '<path d="M8 22h8"/><path d="M7 10h10"/><path d="M12 15v7"/><path d="M12 15a5 5 0 0 0 5-5c0-2-.5-4-1-8H8c-.5 4-1 6-1 8a5 5 0 0 0 5 5Z"/>',
      coffee:       '<path d="M10 2v2"/><path d="M14 2v2"/><path d="M16 8a1 1 0 0 1 1 1v8a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V9a1 1 0 0 1 1-1h14a4 4 0 1 1 0 8h-1"/><path d="M6 2v2"/>',
      cake:         '<path d="M20 21v-8a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8"/><path d="M4 16s.5-1 2-1 2.5 2 4 2 2.5-2 4-2 2.5 2 4 2 2-1 2-1"/><path d="M2 21h20"/><path d="M7 8v3M12 8v3M17 8v3"/><path d="M7 4h.01M12 4h.01M17 4h.01"/>',
      meat:         '<path d="M15.45 15.4c-2.13.65-4.3.32-5.7-1.1-2.29-2.27-1.76-6.5 1.17-9.42 2.93-2.93 7.15-3.46 9.43-1.18 1.41 1.41 1.74 3.57 1.1 5.71-1.4-.51-3.26-.02-4.64 1.36-1.38 1.38-1.87 3.23-1.36 4.63Z"/><path d="m11.25 15.6-2.16 2.16a2.5 2.5 0 1 1-4.56 1.73 2.49 2.49 0 0 1-1.41-4.24 2.5 2.5 0 0 1 3.14-.32l2.16-2.16"/>',
      utensils:     '<path d="M3 2v7c0 1.1.9 2 2 2h0a2 2 0 0 0 2-2V2"/><path d="M7 2v20"/><path d="M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7"/>',
      chef_hat:     '<path d="M17 21a1 1 0 0 0 1-1v-5.35c0-.457.316-.844.727-1.041a4 4 0 0 0-2.134-7.589 5 5 0 0 0-9.186 0 4 4 0 0 0-2.134 7.588c.411.198.727.585.727 1.041V20a1 1 0 0 0 1 1Z"/><path d="M6 17h12"/>',
      leaf:         '<path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z"/><path d="M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12"/>',
      calendar:     '<path d="M8 2v4M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/>',
      users:        '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
      scissors:     '<circle cx="6" cy="6" r="3"/><path d="M8.12 8.12 12 12"/><path d="M20 4 8.12 15.88"/><circle cx="6" cy="18" r="3"/><path d="M14.8 14.8 20 20"/>',
      sparkles:     '<path d="M9.94 14.06A2 2 0 0 0 8.5 12.63l-6.14-1.58a.5.5 0 0 1 0-.96L8.5 8.5A2 2 0 0 0 9.94 7.06L11.52.94a.5.5 0 0 1 .96 0l1.58 6.12A2 2 0 0 0 15.5 8.5l6.14 1.58a.5.5 0 0 1 0 .96L15.5 12.63a2 2 0 0 0-1.44 1.43l-1.58 6.12a.5.5 0 0 1-.96 0Z"/><path d="M20 3v4M22 5h-4"/>',
      wrench:       '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76Z"/>',
      hammer:       '<path d="m15 12-8.5 8.5a2.12 2.12 0 1 1-3-3L12 9"/><path d="M17.64 15 22 10.64"/><path d="m20.91 11.7-1.25-1.25c-.6-.6-.93-1.4-.93-2.25v-.86L16.01 4.6a5.56 5.56 0 0 0-3.94-1.64H9l.92.82A6.18 6.18 0 0 1 12 8.4v1.56l2 2h.86c.85 0 1.65.33 2.25.93l1.25 1.25"/>',
      home_tool:    '<path d="M3 9 12 2l9 7"/><path d="M5 9.5V20a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V9.5"/><path d="m14 13-1 1 2 2-3 3-2-2-1 1"/>',
      home:         '<path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>',
      briefcase:    '<path d="M16 20V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/><rect width="20" height="14" x="2" y="6" rx="2"/>',
      shopping_bag: '<path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z"/><path d="M3 6h18"/><path d="M16 10a4 4 0 0 1-8 0"/>',
      truck:        '<path d="M14 18V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v11a1 1 0 0 0 1 1h2"/><path d="M15 18H9"/><path d="M19 18h2a1 1 0 0 0 1-1v-3.65a1 1 0 0 0-.22-.62l-3.48-4.35A1 1 0 0 0 17.52 8H14"/><circle cx="17" cy="18" r="2"/><circle cx="7" cy="18" r="2"/>',
      heart:        '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/>',
      # Fallback neutro e pulito (non un "sparkle" generico)
      default:      '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>'
    }.freeze

    module_function

    # Restituisce l'SVG completo per il testo di un servizio.
    def icon_for(service_text)
      svg(icon_key_for(service_text))
    end

    # Restituisce la chiave-icona (Symbol) scelta per un testo. Utile nei test.
    def icon_key_for(service_text)
      text = service_text.to_s.downcase
      rule = RULES.find { |keywords, _| keywords.any? { |kw| text.include?(kw) } }
      rule ? rule.last : :default
    end

    # Avvolge l'inner-markup nel tag <svg>. stroke="currentColor" → eredita il colore.
    def svg(key)
      inner = PATHS.fetch(key, PATHS[:default])
      %(<svg viewBox="0 0 24 24" width="26" height="26" fill="none" ) +
        %(stroke="currentColor" stroke-width="2" stroke-linecap="round" ) +
        %(stroke-linejoin="round" aria-hidden="true">#{inner}</svg>)
    end
  end
end
