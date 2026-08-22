# Local character manifest

Place each local character in:

```text
~/Library/Application Support/Frieren Monitor/Characters/<character-id>/
├── character.json
└── spritesheet.png
```

Use relative image filenames without `..` components. Optional `sourceURL` and
`creator` fields preserve attribution for the local pack; the app ignores
unknown metadata fields.

## Legacy V1 atlas

Use this only for a verified 1536x1872, 8-column by 9-row sheet with 192x208
cells:

```json
{
  "schemaVersion": 1,
  "id": "character-id",
  "displayName": "Character name",
  "spritesheet": "spritesheet.png",
  "cellWidth": 192,
  "cellHeight": 208,
  "layout": "legacy-v1",
  "sourceURL": "https://example.com/character",
  "creator": "Creator name"
}
```

## Static image

For one still image, set its full pixel dimensions as the cell size:

```json
{
  "schemaVersion": 1,
  "id": "character-id",
  "displayName": "Character name",
  "spritesheet": "spritesheet.png",
  "cellWidth": 512,
  "cellHeight": 512,
  "layout": "static"
}
```

## Custom atlas

Omit `layout` and provide every animation key. Cells are zero-based `{row,
column}` coordinates:

```json
{
  "schemaVersion": 1,
  "id": "character-id",
  "displayName": "Character name",
  "spritesheet": "spritesheet.png",
  "cellWidth": 128,
  "cellHeight": 128,
  "animations": {
    "idle": [{"row": 0, "column": 0}],
    "runLeft": [{"row": 1, "column": 0}],
    "runRight": [{"row": 2, "column": 0}],
    "hi": [{"row": 3, "column": 0}],
    "reactionOne": [{"row": 4, "column": 0}],
    "reactionTwo": [{"row": 4, "column": 1}],
    "reactionThree": [{"row": 4, "column": 2}],
    "needsPrompt": [{"row": 5, "column": 0}],
    "jump": [{"row": 6, "column": 0}]
  }
}
```

Each key may contain multiple cells. Keep frames in playback order. The app
rejects manifests with missing or empty animation entries, invalid dimensions,
or spritesheet paths outside the character directory.
