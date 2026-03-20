class ApplicationJob < ActiveJob::Base
  # Retry automatico in caso di errori transitori
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Discard job se il record non esiste più (es: Company eliminata)
  discard_on ActiveJob::DeserializationError
end
