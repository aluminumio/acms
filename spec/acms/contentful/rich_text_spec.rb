RSpec.describe Acms::Contentful::RichText do
  def text(value, marks = [])
    { "nodeType" => "text", "value" => value, "marks" => marks.map { |m| { "type" => m } }, "data" => {} }
  end

  def link(type, id)
    { "sys" => { "type" => "Link", "linkType" => type, "id" => id } }
  end

  it "converts every node type into the ACMS tree" do
    document = { "nodeType" => "document", "data" => {}, "content" => [
      { "nodeType" => "heading-2", "data" => {}, "content" => [ text("Head") ] },
      { "nodeType" => "paragraph", "data" => {}, "content" => [
        text("Bold ", %w[bold underline]),
        { "nodeType" => "hyperlink", "data" => { "uri" => "https://x.example" }, "content" => [ text("x") ] },
        { "nodeType" => "entry-hyperlink", "data" => { "target" => link("Entry", "e1") }, "content" => [ text("e") ] },
        { "nodeType" => "entry-hyperlink", "data" => { "target" => link("Entry", "gone") }, "content" => [ text("plain") ] }
      ] },
      { "nodeType" => "ordered-list", "data" => {}, "content" => [ { "nodeType" => "list-item", "data" => {}, "content" => [ { "nodeType" => "paragraph", "data" => {}, "content" => [ text("one") ] } ] } ] },
      { "nodeType" => "embedded-asset-block", "data" => { "target" => link("Asset", "a1") }, "content" => [] },
      { "nodeType" => "embedded-entry-block", "data" => { "target" => link("Entry", "e1") }, "content" => [] },
      { "nodeType" => "blockquote", "data" => {}, "content" => [ { "nodeType" => "paragraph", "data" => {}, "content" => [ text("q") ] } ] },
      { "nodeType" => "hr", "data" => {}, "content" => [] },
      { "nodeType" => "table", "data" => {}, "content" => [ { "nodeType" => "table-row", "data" => {}, "content" => [
        { "nodeType" => "table-header-cell", "data" => {}, "content" => [ { "nodeType" => "paragraph", "data" => {}, "content" => [ text("a") ] } ] },
        { "nodeType" => "table-cell", "data" => {}, "content" => [ { "nodeType" => "paragraph", "data" => {}, "content" => [ text("b") ] } ] }
      ] } ] },
      { "nodeType" => "paragraph", "data" => {}, "content" => [ text("") ] }
    ] }

    tree = described_class.convert(document, entries: { "e1" => { "slug" => "first", "title" => "First" } }, assets: { "a1" => { "filename" => "a.png", "title" => "A" } })
    expect(tree["type"]).to eq("root")
    expect(tree["children"].map { |n| n["type"] }).to eq(%w[heading paragraph list image paragraph blockquote hr paragraph paragraph])
    paragraph = tree["children"][1]["children"]
    expect(paragraph[0]).to eq("type" => "text", "value" => "Bold ", "bold" => true, "underline" => true)
    expect(paragraph[1]).to include("type" => "link", "url" => "https://x.example")
    expect(paragraph[2]).to include("type" => "link", "linkType" => "entry", "target" => "first")
    expect(paragraph[3]).to eq("type" => "text", "value" => "plain")
    expect(tree["children"][2]["children"].first).to eq("type" => "list-item", "children" => [ { "type" => "text", "value" => "one" } ])
    expect(tree["children"][3]).to eq("type" => "image", "src" => "a.png", "alt" => "A")
    expect(tree["children"][4]["children"].first).to include("linkType" => "entry", "target" => "first", "children" => [ { "type" => "text", "value" => "First" } ])
    expect(tree["children"][7]["children"]).to eq([ { "type" => "text", "value" => "a | b" } ])
    expect(tree["children"][8]["children"]).to eq([])
  end
end
