class LinkedDataSignature
  CONTEXT = "https://w3id.org/identity/v1"
  SIGNATURE_CONTEXT = "https://w3id.org/security/v1"

  def initialize(json)
    @json = json.with_indifferent_access
  end

  def verify_actor!
    return unless @json["signature"].is_a?(Hash)

    type        = @json["signature"]["type"]
    creator_uri = @json["signature"]["creator"]
    signature   = @json["signature"]["signatureValue"]

    return unless type == "RsaSignature2017"

    creator = RemoteAccount.find_or_create_by_uri!(uri: creator_uri)

    return if creator.nil?

    options_hash   = hash(@json["signature"].without("type", "id", "signatureValue").merge("@context" => CONTEXT))
    document_hash  = hash(@json.without("signature"))
    to_be_verified = options_hash + document_hash

    creator if creator.keypair.public_key.verify(OpenSSL::Digest.new("SHA256"), Base64.decode64(signature), to_be_verified)
  rescue OpenSSL::PKey::RSAError
    false
  end

  def sign!(creator, sign_with: nil)
    options = {
      "type" => "RsaSignature2017",
      "creator" => "#{creator.uri}#main-key",
      "created" => Time.now.utc.iso8601
    }

    options_hash  = hash(options.without("type", "id", "signatureValue").merge("@context" => CONTEXT))
    document_hash = hash(@json.without("signature"))
    to_be_signed  = options_hash + document_hash
    keypair       = sign_with.present? ? OpenSSL::PKey::RSA.new(sign_with) : creator.keypair

    signature = Base64.strict_encode64(keypair.sign(OpenSSL::Digest.new("SHA256"), to_be_signed))

    # Mastodon's context is either an array or a single URL
    context_with_security = Array(@json["@context"])
    context_with_security << SIGNATURE_CONTEXT
    context_with_security.uniq!
    context_with_security = context_with_security.first if context_with_security.size == 1

    @json.merge("signature" => options.merge("signatureValue" => signature), "@context" => context_with_security)
  end

  private

  def hash(obj)
    Digest::SHA256.hexdigest(canonicalize(obj))
  end

  def canonicalize(json)
    graph = RDF::Graph.new << JSON::LD::API.toRdf(json)
    graph.dump(:normalize)
  end
end
