class_name PokemonGen4TypeLibrary # Maps National Dex species to the first type they had in Generation IV.
extends RefCounted # Keeps immutable species metadata available without a scene-tree node.

const NATIONAL_DEX_MAX: int = 493 # Generation IV ends with Arceus at National Dex 493.

const PRIMARY_TYPE_IDS: Array[int] = [
    12, 12, 12, 10, 10, 10, 11, 11, 11, 7, 7, 7, 7, 7, 7, 1, 1, 1, 1, 1, 1, 1, 4, 4, 13, 13, 5, 5, 4, 4, 4, 4,
    4, 4, 1, 1, 10, 10, 1, 1, 4, 4, 12, 12, 12, 7, 7, 7, 7, 5, 5, 1, 1, 11, 11, 2, 2, 10, 10, 11, 11, 11, 14, 14,
    14, 2, 2, 2, 12, 12, 12, 11, 11, 6, 6, 6, 10, 10, 11, 11, 13, 13, 1, 1, 1, 11, 11, 4, 4, 11, 11, 8, 8, 8, 6, 14,
    14, 11, 11, 13, 13, 12, 12, 5, 5, 2, 2, 1, 4, 4, 5, 5, 1, 12, 1, 11, 11, 11, 11, 11, 11, 14, 7, 15, 13, 10, 7, 1,
    11, 11, 11, 1, 1, 11, 13, 10, 1, 6, 6, 6, 6, 6, 1, 15, 13, 10, 16, 16, 16, 14, 14, 12, 12, 12, 10, 10, 10, 11, 11, 11,
    1, 1, 1, 1, 7, 7, 7, 7, 4, 11, 11, 13, 1, 1, 1, 1, 14, 14, 13, 13, 13, 12, 11, 11, 6, 11, 12, 12, 12, 1, 12, 12,
    7, 11, 11, 14, 17, 17, 11, 8, 14, 14, 1, 7, 7, 1, 5, 9, 1, 1, 11, 7, 7, 7, 17, 1, 1, 10, 10, 15, 15, 11, 11, 11,
    15, 11, 9, 17, 17, 11, 5, 5, 1, 1, 1, 2, 2, 15, 13, 10, 1, 1, 13, 10, 11, 6, 6, 6, 14, 10, 14, 12, 12, 12, 10, 10,
    10, 11, 11, 11, 17, 17, 1, 1, 7, 7, 7, 7, 7, 11, 11, 11, 12, 12, 12, 1, 1, 11, 11, 14, 14, 14, 7, 7, 12, 12, 1, 1,
    1, 7, 7, 7, 1, 1, 1, 2, 2, 1, 6, 1, 1, 17, 9, 9, 9, 9, 2, 2, 13, 13, 13, 13, 7, 7, 12, 4, 4, 11, 11, 11,
    11, 10, 10, 10, 14, 14, 1, 5, 5, 5, 12, 12, 1, 16, 1, 4, 6, 6, 11, 11, 11, 11, 5, 5, 6, 6, 6, 6, 11, 11, 1, 1,
    8, 8, 8, 8, 12, 14, 17, 14, 15, 15, 15, 15, 15, 11, 11, 11, 11, 11, 16, 16, 16, 9, 9, 9, 6, 15, 9, 16, 16, 11, 5, 16,
    9, 14, 12, 12, 12, 10, 10, 10, 11, 11, 11, 1, 1, 1, 1, 1, 7, 7, 13, 13, 13, 12, 12, 6, 6, 6, 6, 7, 7, 7, 7, 7,
    13, 11, 11, 12, 12, 11, 11, 1, 8, 8, 1, 1, 8, 17, 1, 1, 14, 4, 4, 9, 9, 6, 14, 1, 1, 8, 16, 16, 16, 1, 2, 2,
    5, 5, 4, 4, 4, 4, 12, 11, 11, 11, 12, 12, 17, 13, 1, 5, 12, 13, 10, 1, 7, 12, 15, 5, 15, 1, 14, 6, 8, 15, 13, 14,
    14, 14, 9, 11, 10, 1, 8, 14, 11, 11, 17, 12, 1,
] # PokeAPI type IDs, corrected to Generation IV historical types before Fairy existed.

static func get_primary_type_id(dex_number: int) -> int: # Returns the Generation IV slot-one type ID for a National Dex number.
    if dex_number < 1 or dex_number > NATIONAL_DEX_MAX:
        return 0
    return PRIMARY_TYPE_IDS[dex_number - 1]

static func get_primary_type_id_from_species_directory(species_directory: String) -> int: # Reads the numbered sprite-folder name used by PokemonSpriteLibrary.
    var dex_text: String = species_directory.get_file()
    if not dex_text.is_valid_int():
        return 0
    return get_primary_type_id(int(dex_text))

static func get_biome_kind_for_species_directory(species_directory: String) -> int: # Converts the Generation IV primary type into HgssWorldBuilder.BiomeKind order.
    return get_biome_kind_for_type_id(get_primary_type_id_from_species_directory(species_directory))

static func get_biome_kind_for_type_id(type_id: int) -> int: # Maps canonical Pokémon type IDs to the world's seventeen biome enum values.
    match type_id:
        1: return HgssWorldBuilder.BiomeKind.NORMAL
        2: return HgssWorldBuilder.BiomeKind.FIGHTING
        3: return HgssWorldBuilder.BiomeKind.FLYING
        4: return HgssWorldBuilder.BiomeKind.POISON
        5: return HgssWorldBuilder.BiomeKind.GROUND
        6: return HgssWorldBuilder.BiomeKind.ROCK
        7: return HgssWorldBuilder.BiomeKind.BUG
        8: return HgssWorldBuilder.BiomeKind.GHOST
        9: return HgssWorldBuilder.BiomeKind.STEEL
        10: return HgssWorldBuilder.BiomeKind.FIRE
        11: return HgssWorldBuilder.BiomeKind.WATER
        12: return HgssWorldBuilder.BiomeKind.GRASS
        13: return HgssWorldBuilder.BiomeKind.ELECTRIC
        14: return HgssWorldBuilder.BiomeKind.PSYCHIC
        15: return HgssWorldBuilder.BiomeKind.ICE
        16: return HgssWorldBuilder.BiomeKind.DRAGON
        17: return HgssWorldBuilder.BiomeKind.DARK
        _: return -1
