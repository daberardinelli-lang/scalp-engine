class AddServicesCopyToDemos < ActiveRecord::Migration[8.0]
  # Titolo e intro specifici per la sezione Servizi (generati dall'AI).
  # Le descrizioni per-servizio NON hanno una colonna dedicata: vengono salvate
  # dentro la colonna esistente `generated_services`, che ora contiene un array
  # di hash {name, desc} (le demo vecchie hanno un array di stringhe — Demo
  # normalizza entrambi i formati). Scelta meno invasiva: nessuna colonna nuova
  # per le desc, nessun rischio di disallineamento nome↔desc.
  def change
    add_column :demos, :generated_services_title, :string
    add_column :demos, :generated_services_intro, :text
  end
end
