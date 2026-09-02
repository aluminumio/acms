module Acms
  module Contentful
    # Converts a Contentful Rich Text document into the ACMS rich text tree.
    # Embedded assets become image nodes, entry hyperlinks become entry links
    # by slug, tables flatten to one paragraph per row.
    class RichText
      MARKS = %w[bold italic code underline strikethrough].freeze

      # entries: Contentful entry id → { "slug" =>, "title" => }
      # assets:  Contentful asset id → { "filename" =>, "title" => }
      def self.convert(document, entries:, assets:)
        new(entries, assets).root(document)
      end

      def initialize(entries, assets)
        @entries = entries
        @assets = assets
      end

      def root(document)
        { "type" => "root", "children" => blocks(document["content"]) }
      end

      private

      def blocks(nodes)
        Array(nodes).flat_map { |node| block(node) }
      end

      def block(node)
        type = node["nodeType"].to_s
        case type
        when "paragraph" then paragraph(inlines(node["content"]))
        when /\Aheading-(\d)\z/ then { "type" => "heading", "level" => $1.to_i, "children" => inlines(node["content"]) }
        when "unordered-list", "ordered-list"
          list_type = type == "ordered-list" ? "ordered" : "unordered"
          { "type" => "list", "listType" => list_type, "children" => Array(node["content"]).map { |li| list_item(li) } }
        when "blockquote" then { "type" => "blockquote", "children" => blocks(node["content"]) }
        when "hr" then { "type" => "hr" }
        when "embedded-asset-block"
          asset = @assets[target_id(node)]
          asset ? { "type" => "image", "src" => asset["filename"], "alt" => asset["title"].to_s } : []
        when "embedded-entry-block", "embedded-entry-inline"
          link = entry_link(node)
          link ? paragraph([ link ]) : []
        when "table"
          Array(node["content"]).map { |row| paragraph([ { "type" => "text", "value" => row_text(row) } ]) }
        else
          node["content"] ? paragraph(inlines(node["content"])) : []
        end
      end

      def list_item(node)
        children = Array(node["content"]).flat_map do |child|
          case child["nodeType"]
          when "paragraph" then inlines(child["content"])
          when "unordered-list", "ordered-list" then [ block(child) ]
          else Array(block(child)).flat_map { |b| b["children"] || [] }
          end
        end
        { "type" => "list-item", "children" => children }
      end

      def inlines(nodes)
        Array(nodes).flat_map { |node| inline(node) }
      end

      def inline(node)
        case node["nodeType"]
        when "text"
          value = node["value"].to_s
          return [] if value.empty?

          text = { "type" => "text", "value" => value }
          Array(node["marks"]).each { |m| text[m["type"]] = true if MARKS.include?(m["type"]) }
          [ text ]
        when "hyperlink"
          [ { "type" => "link", "url" => node.dig("data", "uri").to_s, "children" => inlines(node["content"]) } ]
        when "entry-hyperlink"
          slug = @entries.dig(target_id(node), "slug")
          slug ? [ { "type" => "link", "linkType" => "entry", "target" => slug, "children" => inlines(node["content"]) } ] : inlines(node["content"])
        when "asset-hyperlink"
          filename = @assets.dig(target_id(node), "filename")
          filename ? [ { "type" => "link", "url" => "/assets/#{filename}", "children" => inlines(node["content"]) } ] : inlines(node["content"])
        when "embedded-entry-inline"
          Array(entry_link(node))
        else
          node["content"] ? inlines(node["content"]) : []
        end
      end

      def entry_link(node)
        target = @entries[target_id(node)]
        return nil unless target

        label = target["title"].to_s.empty? ? target["slug"] : target["title"]
        { "type" => "link", "linkType" => "entry", "target" => target["slug"], "children" => [ { "type" => "text", "value" => label } ] }
      end

      def row_text(row)
        Array(row["content"]).map { |cell| plain_text(cell) }.join(" | ")
      end

      def plain_text(node)
        return node["value"].to_s if node["nodeType"] == "text"

        Array(node["content"]).map { |c| plain_text(c) }.join
      end

      def target_id(node)
        node.dig("data", "target", "sys", "id")
      end

      def paragraph(children)
        { "type" => "paragraph", "children" => children }
      end
    end
  end
end
