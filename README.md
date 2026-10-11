# acms

Ruby client and CLI for [Agent Content Management](https://agentcontentmanagement.com),
an agent-first CMS whose API is authenticated by an EIP-191 wallet signature.
Includes an importer that moves a Contentful space into a site, and a verifier
that diffs the space against the site's Contentful-compatible delivery API.

## Install

```ruby
gem "acms", github: "aluminumio/acms"
```

## Client

```ruby
wallet = Acms::Wallet.generate            # or Acms::Wallet.new(private_key_hex)
client = Acms::Client.new(wallet: wallet) # base_url: defaults to https://agentcontentmanagement.com

client.redeem_invite("CODE")              # accept an invite → membership
site   = client.site(site_id)
client.create_entry(site_id, title: "Hello", entry_type_id: type_id, data: { body: "# Hi" }, published: true)
client.create_asset(site_id, file: File.binread("logo.png"), filename: "logo.png", content_type: "image/png")
client.leave_site(site_id)                # give up the wallet's own membership

export = client.export_site(site_id)      # queued; poll client.site_export(site_id, export["id"])
client.site_exports(site_id)              # newest first: name, status, byte_size, download_url
client.download(export["download_url"])   # the ZIP bytes (follows the storage redirect)
client.delete_site(site_id, confirm_export: export["name"])
```

Every request is signed with a fresh five-minute token; nothing is stored.
Non-2xx responses raise `Acms::Error` with `status` and `body`.

## CLI

```
acms wallet new                       print a fresh private key and address
acms invite redeem CODE               accept an invite with your key
acms contentful dump   --file F       pull a Contentful space into a JSON file
acms contentful import --site S       import a Contentful space (API or --file) into site S
acms contentful verify --site S       diff a Contentful space against site S's delivery API
acms sites:export SITE [-o FILE]      export site SITE, wait, print its name and download URL
acms sites:exports SITE               list SITE's exports, newest first
acms sites:delete SITE --confirm-export NAME [--yes]
                                      delete SITE for good (asks for the slug unless --yes)
```

The ACMS key comes from `--key` or `ACMS_PRIVATE_KEY`; the API host from
`--api-url` or `ACMS_API_URL`. Contentful credentials come from the same
variables the Contentful SDKs read (`CONTENTFUL_SPACE_ID`,
`CONTENTFUL_ACCESS_TOKEN`, `CONTENTFUL_API_URL`, `CONTENTFUL_ENVIRONMENT`) or
the matching flags.

A typical migration:

```
acms wallet new                                   # keep the key; have the site owner mint an invite
acms invite redeem <code>
acms contentful dump --file space.json
acms contentful import --site <site id> --file space.json
acms contentful verify --site <site id> --file space.json
```

Then point the site at its Contentful-compatible endpoint: `GET /api/v1/sites/:id`
returns `contentful.api_url`, `space_id` and `access_token` for any Contentful SDK.

## Deleting a site

A delete needs a fresh export first. The server refuses it (422) unless
`--confirm-export` is the name of the site's newest export, that export is
complete, under 24 hours old, and no older than the last content change, and
the site has no domains. Only an owner or admin wallet may delete. The delete
removes the site's exports too, so save the ZIP:

```
acms sites:export <site id> -o site.zip           # prints name=<slug>-<UTC timestamp>
acms sites:delete <site id> --confirm-export <name>
```

## What the importer maps

| Contentful | ACMS |
|---|---|
| Symbol / Text | string / markdown |
| RichText | rich_text tree (embedded assets → image nodes; tables flatten to one paragraph per row) |
| Integer / Number, Date, Boolean | number, date, boolean |
| Link (Asset / Entry) | image / reference |
| Array of Link (Asset / Entry) | images / references |
| Array of Symbol | strings |
| Object, Location | json |

Entry `sys.id` is kept in `metadata.contentful_id` and each field's original
id and type in `validations.contentful`, so the site's delivery API answers
with the original identity. The default Contentful locale maps onto the site's
default locale; other locales become translation entries holding only their
localized values. Re-running an import updates in place.

## Development

```
bundle install
bundle exec rspec
bundle exec rubocop
```
