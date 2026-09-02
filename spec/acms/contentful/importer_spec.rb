RSpec.describe Acms::Contentful::Importer do
  def link(type, id)
    { "sys" => { "type" => "Link", "linkType" => type, "id" => id } }
  end

  def field(id, type, **extra)
    { "id" => id, "name" => id, "type" => type, "localized" => false, "required" => false, "omitted" => false }.merge(extra.transform_keys(&:to_s))
  end

  let(:data) do
    {
      "locales" => [ { "code" => "en-US", "default" => true }, { "code" => "es", "default" => false } ],
      "content_types" => [
        { "sys" => { "id" => "blogAuthor" }, "name" => "Author", "displayField" => "name", "fields" => [ field("name", "Symbol"), field("avatar", "Link", linkType: "Asset") ] },
        { "sys" => { "id" => "blogPost" }, "name" => "Post", "displayField" => "title", "fields" => [
          field("title", "Symbol", localized: true), field("slug", "Symbol"), field("publishedOn", "Date"),
          field("authors", "Array", items: { "type" => "Link", "linkType" => "Entry", "validations" => [ { "linkContentType" => [ "blogAuthor" ] } ] }),
          field("gallery", "Array", items: { "type" => "Link", "linkType" => "Asset" }),
          field("tags", "Array", items: { "type" => "Symbol" }),
          field("meta", "Object"), field("secret", "Symbol", omitted: true)
        ] }
      ],
      "assets" => [
        { "sys" => { "id" => "a1" }, "fields" => { "title" => { "en-US" => "Ada" }, "file" => { "en-US" => { "url" => "//img.example/a.png", "fileName" => "ada.png", "contentType" => "image/png" } } } },
        { "sys" => { "id" => "a2" }, "fields" => { "title" => { "en-US" => "Cover" }, "file" => { "en-US" => { "url" => "//img.example/c.png", "fileName" => "cover.png", "contentType" => "image/png" } } } }
      ],
      "entries" => [
        { "sys" => { "id" => "author1", "createdAt" => "2026-01-05T10:00:00Z", "contentType" => link("ContentType", "blogAuthor") },
          "fields" => { "name" => { "en-US" => "Ada Lovelace" }, "avatar" => { "en-US" => link("Asset", "a1") } } },
        { "sys" => { "id" => "post1", "createdAt" => "2026-01-06T10:00:00Z", "contentType" => link("ContentType", "blogPost") },
          "fields" => { "title" => { "en-US" => "First post", "es" => "Primera" }, "slug" => { "en-US" => "first-post" }, "publishedOn" => { "en-US" => "2026-01-10" },
                        "authors" => { "en-US" => [ link("Entry", "author1"), link("Entry", "gone") ] }, "gallery" => { "en-US" => [ link("Asset", "a2") ] },
                        "tags" => { "en-US" => %w[a b] }, "meta" => { "en-US" => { "k" => 1 } } } }
      ]
    }
  end

  let(:client) { instance_double(Acms::Client) }
  let(:downloads) { [] }

  before do
    allow(client).to receive(:site).and_return("id" => "s1", "settings" => { "default_locale" => "en" })
    allow(client).to receive(:update_site)
    allow(client).to receive(:assets).and_return([ { "id" => "asset-cover", "filename" => "cover.png" } ])
    allow(client).to receive(:update_asset)
    allow(client).to receive(:create_asset) { |_, filename:, **| { "id" => "asset-#{filename}" } }
    allow(client).to receive(:entry_types).and_return([ { "id" => "t-author", "slug" => "blog_author", "name" => "Author", "field_definitions" => [ { "id" => "f1", "slug" => "name", "name" => "Name", "field_type" => "string" }, { "id" => "f9", "slug" => "bio", "name" => "Bio", "field_type" => "text" } ] } ])
    allow(client).to receive(:update_entry_type) { |_, id, attrs, fields:| { "id" => id, "slug" => "blog_author" }.merge(attrs) }
    allow(client).to receive(:create_entry_type) { |_, attrs, fields:| { "id" => "t-#{attrs[:slug]}", "slug" => attrs[:slug] } }
    allow(client).to receive(:entries).and_return([])
    allow(client).to receive(:create_entry) { |_, attrs| { "id" => "e-#{attrs[:slug]}-#{attrs[:locale]}", "slug" => attrs[:slug], "locale" => attrs[:locale] } }
    allow(client).to receive(:update_entry) { |_, id, attrs| { "id" => id }.merge(attrs) }
  end

  it "imports through the API, preserving identity and reusing what exists" do
    importer = described_class.new(client, "s1", data, downloader: ->(url) { downloads << url; "png" })
    counts = importer.import!
    expect(counts).to include(assets: 2, entry_types: 2, entries: 2, translations: 1)

    expect(client).to have_received(:update_site).with("s1", settings: { "default_locale" => "en", "supported_locales" => [ "es" ] })

    # the existing cover.png is updated, not re-uploaded; ada.png is downloaded and created
    expect(downloads).to eq([ "https://img.example/a.png" ])
    expect(client).to have_received(:update_asset).with("s1", "asset-cover", alt_text: "Cover")
    expect(client).to have_received(:create_asset).with("s1", hash_including(file: "png", filename: "ada.png", content_type: "image/png", alt_text: "Ada", source: "migrated-unknown"))

    # the existing author type keeps its extra `bio` field and updates `name` by id
    expect(client).to have_received(:update_entry_type).with("s1", "t-author", { name: "Author" }, fields: array_including(
      hash_including(id: "f1", slug: "name", field_type: "string"),
      hash_including(slug: "avatar", field_type: "image"),
      hash_including(id: "f9", slug: "bio")
    ))
    expect(client).to have_received(:create_entry_type).with("s1", { name: "Post", slug: "blog_post", path_prefix: "blog-post" }, fields: array_including(
      hash_including(slug: "authors", field_type: "references", validations: hash_including("entry_type" => "blog_author")),
      hash_including(slug: "gallery", field_type: "images"),
      hash_including(slug: "tags", field_type: "strings"),
      hash_including(slug: "meta", field_type: "json"),
      hash_including(slug: "title", required: false)
    ))
    expect(client).not_to have_received(:create_entry_type).with("s1", anything, fields: array_including(hash_including(slug: "secret")))

    expect(client).to have_received(:create_entry).with("s1", hash_including(
      entry_type_id: "t-blog_post", locale: "en", title: "First post", slug: "first-post", published: true, published_at: "2026-01-06T10:00:00Z",
      metadata: { "contentful_id" => "post1" },
      data: { "title" => "First post", "slug" => "first-post", "published_on" => "2026-01-10", "authors" => [ "ada-lovelace" ], "gallery" => [ "cover.png" ], "tags" => %w[a b], "meta" => { "k" => 1 } }
    ))
    expect(client).to have_received(:create_entry).with("s1", hash_including(
      locale: "es", title: "Primera", slug: "first-post", canonical_entry_id: "e-first-post-en", data: { "title" => "Primera" }
    ))
    expect(client).to have_received(:create_entry).with("s1", hash_including(entry_type_id: "t-author", title: "Ada Lovelace", slug: "ada-lovelace", data: { "name" => "Ada Lovelace", "avatar" => "ada.png" }))
  end

  it "updates entries it has imported before instead of creating duplicates" do
    allow(client).to receive(:entries).and_return([ { "id" => "old", "entry_type_id" => "t-blog_post", "entry_type_slug" => "blog_post", "slug" => "first-post", "locale" => "en", "metadata" => { "contentful_id" => "post1" }, "published_at" => "2026-01-06T10:00:00Z" } ])
    described_class.new(client, "s1", data, downloader: ->(_) { "png" }).import!
    expect(client).to have_received(:update_entry).with("s1", "old", hash_including(title: "First post"))
    expect(client).not_to have_received(:create_entry).with("s1", hash_including(locale: "en", slug: "first-post"))
  end
end
