-- docx-title-page.lua
--
-- Pandoc's docx writer only stringifies author names; it drops affiliations,
-- ORCID, and the corresponding-author marker that the html/pdf writers render
-- automatically. Quarto normalizes the YAML `author:` field into a `by-author`
-- metadata key where each author already has their affiliations embedded
-- (with a pre-assigned `.number`), and a top-level `affiliations` key with the
-- deduplicated, numbered affiliation list. This filter uses that normalized
-- data to build an equivalent title block for docx.

local stringify = pandoc.utils.stringify

local function get_name(author)
  local given = author.name.given and stringify(author.name.given) or ""
  local family = author.name.family and stringify(author.name.family) or ""
  local name = (given .. " " .. family):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" and author.name.literal then
    name = stringify(author.name.literal)
  end
  return name
end

local function is_corresponding(author)
  return author.attributes and author.attributes.corresponding
    and stringify(author.attributes.corresponding) == "true"
end

local function affil_text(affil)
  local parts = {}
  if affil.department then table.insert(parts, stringify(affil.department)) end
  if affil.name then table.insert(parts, stringify(affil.name)) end
  if affil.address then table.insert(parts, stringify(affil.address)) end
  if affil.country then table.insert(parts, stringify(affil.country)) end
  return table.concat(parts, ", ")
end

function Pandoc(doc)
  if not quarto.doc.is_format("docx") then
    return doc
  end

  local meta = doc.meta
  local authors = meta["by-author"]
  if not authors then
    return doc
  end

  local new_blocks = {}
  local corresponding_email = nil

  -- Author line, each author on its own line via a hard line break
  local author_inlines = {}
  for _, author in ipairs(authors) do
    local name = get_name(author)

    local nums = {}
    if author.affiliations then
      for _, affil in ipairs(author.affiliations) do
        table.insert(nums, tostring(affil.number))
      end
    end

    local sup_inlines = {}
    for i, n in ipairs(nums) do
      if i > 1 then table.insert(sup_inlines, pandoc.Str(",")) end
      table.insert(sup_inlines, pandoc.Str(n))
    end
    if is_corresponding(author) then
      table.insert(sup_inlines, pandoc.Str("*"))
      if author.email then corresponding_email = stringify(author.email) end
    end

    table.insert(author_inlines, pandoc.Str(name))
    if #sup_inlines > 0 then
      table.insert(author_inlines, pandoc.Superscript(sup_inlines))
    end
    if author.orcid then
      table.insert(author_inlines, pandoc.Str(", " .. stringify(author.orcid)))
    end
    table.insert(author_inlines, pandoc.LineBreak())
  end
  table.remove(author_inlines) -- drop trailing line break
  table.insert(new_blocks, pandoc.Para(author_inlines))

  -- Numbered affiliation list, ordered by Quarto's assigned affiliation number
  if meta.affiliations then
    local affil_list = {}
    for _, affil in ipairs(meta.affiliations) do
      table.insert(affil_list, affil)
    end
    table.sort(affil_list, function(a, b) return a.number < b.number end)

    local affil_inlines = {}
    for i, affil in ipairs(affil_list) do
      if i > 1 then table.insert(affil_inlines, pandoc.LineBreak()) end
      table.insert(affil_inlines, pandoc.Superscript({ pandoc.Str(tostring(affil.number)) }))
      table.insert(affil_inlines, pandoc.Str(" " .. affil_text(affil)))
    end
    table.insert(new_blocks, pandoc.Para(affil_inlines))
  end

  -- Corresponding author line
  if corresponding_email then
    table.insert(new_blocks, pandoc.Para({
      pandoc.Str("*Corresponding author: " .. corresponding_email)
    }))
  end

  -- Abstract (kept as parsed inlines so *italics* etc. are preserved)
  if meta.abstract then
    table.insert(new_blocks, pandoc.Header(2, { pandoc.Str("Abstract") }))
    table.insert(new_blocks, pandoc.Para(meta.abstract))
  end

  -- Keywords
  if meta.keywords then
    local kw_inlines = { pandoc.Strong({ pandoc.Str("Key words:") }), pandoc.Str(" ") }
    for i, kw in ipairs(meta.keywords) do
      if i > 1 then table.insert(kw_inlines, pandoc.Str("; ")) end
      table.insert(kw_inlines, pandoc.Span(kw))
    end
    table.insert(new_blocks, pandoc.Para(kw_inlines))
  end

  -- Prepend the generated title block to the document body
  for i = #new_blocks, 1, -1 do
    table.insert(doc.blocks, 1, new_blocks[i])
  end

  -- Suppress pandoc's own plain title-block fields so they aren't duplicated
  meta.author = nil
  meta.date = nil
  meta.abstract = nil

  return pandoc.Pandoc(doc.blocks, meta)
end
