module Acms
  module Contentful
    # Imports a Contentful space into a site through the ACMS agent API:
    # content types → entry types and fields, assets → assets (bytes
    # downloaded and uploaded), entries → entries with one translation entry
    # per extra locale. Input is the Delivery API's own JSON fetched with
    # locale=* (Fetcher).
    #
    # Identity is preserved so the site's Contentful-compatible API answers
    # with the original ids: entry sys.id → metadata.contentful_id, field
    # id/type → validations.contentful. Re-running updates in place (types by
    # slug, entries by contentful_id, assets by filename).
    class Importer
      TYPE_MAP = {
        "Symbol" => "string", "Text" => "markdown", "RichText" => "rich_text",
        "Integer" => "number", "Number" => "number", "Date" => "date", "Boolean" => "boolean",
        "Object" => "json", "Location" => "json"
      }.freeze

      attr_reader :counts

      def initialize(client, site_id, data, downloader: Fetcher.method(:download), logger: nil)
        @client = client
        @site_id = site_id
        @data = data
        @downloader = downloader
        @log = logger
        @counts = Hash.new(0)
        @types = {}     # Contentful content type id → entry type JSON (with field_definitions)
        @fields = {}    # content type id → { field id → field slug }
        @display = {}   # content type id → displayField
        @assets = {}    # Contentful asset id → { "filename", "title" }
        @entries = {}   # Contentful entry id → { "slug", "title", "type" }
      end

      def import!
        site = @client.site(@site_id)
        @default_locale = site.dig("settings", "default_locale").to_s.empty? ? "en" : site["settings"]["default_locale"]
        import_locales(site)
        import_assets
        import_content_types
        import_entries
        counts
      end

      private

      def log(message)
        @log&.call(message)
      end

      # ---- locales --------------------------------------------------------

      def import_locales(site)
        locales = Array(@data["locales"])
        default = locales.find { |l| l["default"] } || locales.first || { "code" => @default_locale }
        @cf_default = default["code"]
        @locale_map = { @cf_default => @default_locale }
        locales.each { |l| @locale_map[l["code"]] ||= l["code"] }
        extra = @locale_map.values - [ @default_locale ]
        return if extra.empty?

        settings = site["settings"] || {}
        supported = Array(settings["supported_locales"]) | extra
        return if supported == Array(settings["supported_locales"])

        @client.update_site(@site_id, settings: settings.merge("supported_locales" => supported))
      end

      # ---- assets ---------------------------------------------------------

      def import_assets
        existing = @client.assets(@site_id).to_h { |a| [ a["filename"], a ] }
        Array(@data["assets"]).each do |raw|
          file = localized(raw.dig("fields", "file"))
          next unless file.is_a?(Hash) && !file["url"].to_s.empty?

          id = raw.dig("sys", "id")
          filename = unique_filename(file["fileName"], id)
          title = localized(raw.dig("fields", "title")).to_s
          alt = localized(raw.dig("fields", "description")).to_s
          alt = title if alt.empty?
          log("asset #{filename}")

          if existing[filename]
            @client.update_asset(@site_id, existing[filename]["id"], alt_text: alt)
          else
            bytes = @downloader.call(absolute_url(file["url"]))
            @client.create_asset(@site_id, file: bytes, filename: filename, content_type: file["contentType"],
                                            alt_text: alt, source: "migrated-unknown", license_type: "unknown",
                                            notes: "Imported from Contentful asset #{id}")
          end
          @assets[id] = { "filename" => filename, "title" => title }
          @counts[:assets] += 1
        end
      end

      def unique_filename(name, id)
        name = File.basename(name.to_s.strip.empty? ? id : name.to_s.strip)
        @assets.values.any? { |a| a["filename"] == name } ? "#{id}-#{name}" : name
      end

      def absolute_url(url)
        url.start_with?("//") ? "https:#{url}" : url
      end

      # ---- content types --------------------------------------------------

      def import_content_types
        existing = @client.entry_types(@site_id).to_h { |t| [ t["slug"], t ] }
        Array(@data["content_types"]).each do |ct|
          id = ct.dig("sys", "id")
          slug = underscore(id)
          log("content type #{id}")
          fields = Array(ct["fields"]).reject { |f| f["omitted"] }.map { |f| field_attrs(f) }

          type = if (current = existing[slug])
            # Keep fields the site already has that the space does not know about.
            known = fields.map { |f| f[:slug] }
            kept = Array(current["field_definitions"]).reject { |f| known.include?(f["slug"]) }
                                                       .map { |f| { id: f["id"], name: f["name"], slug: f["slug"], field_type: f["field_type"], hint: f["hint"], localization: f["localization"] } }
            merged = fields.map { |f| (match = Array(current["field_definitions"]).find { |d| d["slug"] == f[:slug] }) ? f.merge(id: match["id"]) : f }
            @client.update_entry_type(@site_id, current["id"], { name: current["name"] }, fields: merged + kept)
          else
            attrs = { name: ct["name"].to_s.empty? ? id : ct["name"], slug: slug }
            attrs[:path_prefix] = slug.tr("_", "-") unless slug == "page"
            @client.create_entry_type(@site_id, attrs, fields: fields)
          end

          @types[id] = type
          @display[id] = ct["displayField"]
          @fields[id] = Array(ct["fields"]).to_h { |f| [ f["id"], { "slug" => underscore(f["id"]), "meta" => f } ] }
          @counts[:entry_types] += 1
        end
      end

      def field_attrs(field)
        attrs = {
          name: field["name"].to_s.empty? ? field["id"] : field["name"],
          slug: underscore(field["id"]),
          field_type: field_type_for(field),
          required: field["required"] == true,
          validations: { "contentful" => field.slice("id", "type", "linkType", "items").compact }
        }
        attrs[:localization] = "organizational" unless field["localized"]
        target = link_content_types(field)
        attrs[:validations]["entry_type"] = underscore(target.first) if target.size == 1
        attrs
      end

      def field_type_for(field)
        case field["type"]
        when "Link" then field["linkType"] == "Asset" ? "image" : "reference"
        when "Array"
          items = field["items"] || {}
          if items["type"] == "Link"
            items["linkType"] == "Asset" ? "images" : "references"
          elsif items["type"] == "Symbol"
            "strings"
          else
            "json"
          end
        else TYPE_MAP.fetch(field["type"], "json")
        end
      end

      def link_content_types(field)
        validations = field["type"] == "Array" ? field.dig("items", "validations") : field["validations"]
        Array(validations).flat_map { |v| Array(v["linkContentType"]) }.uniq
      end

      # ---- entries --------------------------------------------------------

      def import_entries
        entries = Array(@data["entries"]).select { |e| @types[content_type_id(e)] }
        entries.each { |e| @entries[e.dig("sys", "id")] = { "slug" => slug_for(e), "type" => content_type_id(e) } }
        entries.each { |e| @entries[e.dig("sys", "id")]["title"] = title_for(e, @cf_default) }

        existing = @client.entries(@site_id)
        @by_contentful_id = existing.group_by { |e| [ e.dig("metadata", "contentful_id"), e["locale"] ] }
        @by_slug = existing.to_h { |e| [ [ e["entry_type_slug"], e["slug"], e["locale"] ], e ] }

        entries.each { |e| import_entry(e) }
      end

      def content_type_id(entry)
        entry.dig("sys", "contentType", "sys", "id")
      end

      def slug_for(entry)
        ct = content_type_id(entry)
        fields = entry["fields"] || {}
        slug = parameterize(localized(fields["slug"]))
        slug = parameterize(localized(fields[@display[ct]])) if slug.empty?
        slug = entry.dig("sys", "id") if slug.empty?
        taken = @entries.values.any? { |e| e["type"] == ct && e["slug"] == slug }
        taken ? "#{slug}-#{entry.dig('sys', 'id').to_s[0, 6].downcase}" : slug
      end

      def import_entry(raw)
        ct = content_type_id(raw)
        type = @types[ct]
        id = raw.dig("sys", "id")
        slug = @entries[id]["slug"]
        created = raw.dig("sys", "createdAt")
        log("entry #{id} (#{slug})")

        base = save_entry(type, id, slug, @default_locale,
                          title: title_for(raw, @cf_default), data: values_for(raw, @cf_default), published_at: created)
        @counts[:entries] += 1

        (locales_in(raw) - [ @cf_default ]).each do |code|
          locale = @locale_map[code] || code
          next if locale == @default_locale

          save_entry(type, id, slug, locale,
                     title: title_for(raw, code), data: values_for(raw, code, only_present: true),
                     published_at: created, canonical_entry_id: base["id"])
          @counts[:translations] += 1
        end
      end

      def save_entry(type, contentful_id, slug, locale, attrs)
        current = @by_contentful_id[[ contentful_id, locale ]]&.find { |e| e["entry_type_id"] == type["id"] } ||
                  @by_slug[[ type["slug"], slug, locale ]]
        payload = attrs.merge(slug: slug, published: true, metadata: { "contentful_id" => contentful_id })
        if current
          payload.delete(:published_at) if current["published_at"]
          @client.update_entry(@site_id, current["id"], payload)
        else
          @client.create_entry(@site_id, payload.merge(entry_type_id: type["id"], locale: locale))
        end
      end

      def title_for(raw, code)
        fields = raw["fields"] || {}
        display = @display[content_type_id(raw)]
        [ fields[display], fields["title"], fields["name"] ].each do |candidate|
          value = localized(candidate, code).to_s
          return value unless value.empty?
        end
        @entries.dig(raw.dig("sys", "id"), "slug")
      end

      def locales_in(raw)
        (raw["fields"] || {}).values.flat_map { |by_locale| by_locale.is_a?(Hash) ? by_locale.keys : [] }.uniq
      end

      def values_for(raw, code, only_present: false)
        defs = @fields[content_type_id(raw)]
        (raw["fields"] || {}).each_with_object({}) do |(field_id, by_locale), data|
          fd = defs[field_id]
          next unless fd && by_locale.is_a?(Hash)
          next if only_present && !by_locale.key?(code)

          value = by_locale.key?(code) ? by_locale[code] : by_locale[@cf_default]
          converted = convert(value, fd["meta"])
          data[fd["slug"]] = converted unless converted.nil?
        end
      end

      def convert(value, meta)
        return nil if value.nil?

        case meta["type"]
        when "Link" then link_ref(value)
        when "Array" then meta.dig("items", "type") == "Link" ? Array(value).filter_map { |l| link_ref(l) } : value
        when "RichText" then RichText.convert(value, entries: @entries, assets: @assets)
        else value
        end
      end

      def link_ref(link)
        sys = link.is_a?(Hash) ? link["sys"] : nil
        return nil unless sys.is_a?(Hash)

        sys["linkType"] == "Asset" ? @assets.dig(sys["id"], "filename") : @entries.dig(sys["id"], "slug")
      end

      def localized(by_locale, code = @cf_default)
        return by_locale unless by_locale.is_a?(Hash) && (by_locale.key?(code) || by_locale.key?(@cf_default))

        by_locale.key?(code) ? by_locale[code] : by_locale[@cf_default]
      end

      # ---- string helpers (no ActiveSupport in the gem) ---------------------

      def underscore(camel)
        camel.to_s.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').tr("-", "_").downcase
      end

      def parameterize(value)
        value.to_s.downcase.gsub(/[^a-z0-9\-_]+/, "-").gsub(/-{2,}/, "-").gsub(/\A-|-\z/, "")
      end
    end
  end
end
