"""Shipping prices per region, tier and service level."""

import math

FREE_SHIPPING_THRESHOLD = 150.0
VOLUMETRIC_DIVISOR = 5000.0
TIER_LIMITS_KG = (1.0, 5.0, 20.0)
TIER_MULTIPLIERS = (1.0, 1.5, 2.4, 4.0)
SERVICE_LEVELS = ("economy", "standard", "express")
SERVICE_FACTORS = {"economy": 0.85, "standard": 1.0, "express": 1.75}

REGION_RATES = {
    "north-america": {
        "code": "NA",
        "base": 4.20,
        "per_kg": 0.90,
        "remote": False,
    },
    "south-america": {
        "code": "SA",
        "base": 6.80,
        "per_kg": 1.40,
        "remote": False,
    },
    "western-europe": {
        "code": "WE",
        "base": 5.10,
        "per_kg": 1.10,
        "remote": False,
    },
    "eastern-europe": {
        "code": "EE",
        "base": 5.60,
        "per_kg": 1.20,
        "remote": False,
    },
    "nordics": {
        "code": "NO",
        "base": 5.90,
        "per_kg": 1.25,
        "remote": False,
    },
    "british-isles": {
        "code": "BI",
        "base": 5.30,
        "per_kg": 1.15,
        "remote": False,
    },
    "iberia": {
        "code": "IB",
        "base": 5.40,
        "per_kg": 1.15,
        "remote": False,
    },
    "balkans": {
        "code": "BK",
        "base": 6.10,
        "per_kg": 1.30,
        "remote": False,
    },
    "baltics": {
        "code": "BT",
        "base": 6.00,
        "per_kg": 1.30,
        "remote": False,
    },
    "caucasus": {
        "code": "CA",
        "base": 7.20,
        "per_kg": 1.50,
        "remote": False,
    },
    "middle-east": {
        "code": "ME",
        "base": 7.40,
        "per_kg": 1.55,
        "remote": False,
    },
    "north-africa": {
        "code": "NF",
        "base": 7.90,
        "per_kg": 1.60,
        "remote": False,
    },
    "west-africa": {
        "code": "WF",
        "base": 8.60,
        "per_kg": 1.80,
        "remote": False,
    },
    "east-africa": {
        "code": "EF",
        "base": 8.80,
        "per_kg": 1.85,
        "remote": False,
    },
    "southern-africa": {
        "code": "SF",
        "base": 8.20,
        "per_kg": 1.70,
        "remote": False,
    },
    "central-asia": {
        "code": "CS",
        "base": 7.70,
        "per_kg": 1.60,
        "remote": False,
    },
    "south-asia": {
        "code": "SS",
        "base": 6.90,
        "per_kg": 1.45,
        "remote": False,
    },
    "southeast-asia": {
        "code": "SE",
        "base": 6.40,
        "per_kg": 1.35,
        "remote": False,
    },
    "east-asia": {
        "code": "EA",
        "base": 5.80,
        "per_kg": 1.25,
        "remote": False,
    },
    "oceania": {
        "code": "OC",
        "base": 7.10,
        "per_kg": 1.50,
        "remote": False,
    },
    "pacific-islands": {
        "code": "PI",
        "base": 9.40,
        "per_kg": 2.00,
        "remote": True,
    },
    "caribbean": {
        "code": "CB",
        "base": 7.30,
        "per_kg": 1.55,
        "remote": False,
    },
    "central-america": {
        "code": "CM",
        "base": 6.60,
        "per_kg": 1.40,
        "remote": False,
    },
    "andes": {
        "code": "AN",
        "base": 7.00,
        "per_kg": 1.50,
        "remote": False,
    },
    "arctic": {
        "code": "AR",
        "base": 11.50,
        "per_kg": 2.60,
        "remote": True,
    },
    "antarctic": {
        "code": "AQ",
        "base": 14.00,
        "per_kg": 3.20,
        "remote": True,
    },
}


class UnknownRegion(KeyError):
    pass


class UnknownServiceLevel(KeyError):
    pass


def region_rate(region):
    try:
        return REGION_RATES[region]
    except KeyError:
        raise UnknownRegion(region) from None


def region_code(region):
    return region_rate(region)["code"]


def is_remote(region):
    return region_rate(region)["remote"]


def service_factor(level):
    try:
        return SERVICE_FACTORS[level]
    except KeyError:
        raise UnknownServiceLevel(level) from None


def volumetric_weight(length_cm, width_cm, height_cm):
    return (length_cm * width_cm * height_cm) / VOLUMETRIC_DIVISOR


def billable_weight(actual_kg, length_cm, width_cm, height_cm):
    return max(actual_kg, volumetric_weight(length_cm, width_cm, height_cm))


def round_up_to_half_kg(weight_kg):
    return math.ceil(weight_kg * 2) / 2


def north_america_base():
    return region_rate("north-america")["base"]


def north_america_per_kg():
    return region_rate("north-america")["per_kg"]


def south_america_base():
    return region_rate("south-america")["base"]


def south_america_per_kg():
    return region_rate("south-america")["per_kg"]


def western_europe_base():
    return region_rate("western-europe")["base"]


def western_europe_per_kg():
    return region_rate("western-europe")["per_kg"]


def eastern_europe_base():
    return region_rate("eastern-europe")["base"]


def eastern_europe_per_kg():
    return region_rate("eastern-europe")["per_kg"]


def nordics_base():
    return region_rate("nordics")["base"]


def nordics_per_kg():
    return region_rate("nordics")["per_kg"]


def british_isles_base():
    return region_rate("british-isles")["base"]


def british_isles_per_kg():
    return region_rate("british-isles")["per_kg"]


def iberia_base():
    return region_rate("iberia")["base"]


def iberia_per_kg():
    return region_rate("iberia")["per_kg"]


def balkans_base():
    return region_rate("balkans")["base"]


def balkans_per_kg():
    return region_rate("balkans")["per_kg"]


def baltics_base():
    return region_rate("baltics")["base"]


def baltics_per_kg():
    return region_rate("baltics")["per_kg"]


def caucasus_base():
    return region_rate("caucasus")["base"]


def caucasus_per_kg():
    return region_rate("caucasus")["per_kg"]


def middle_east_base():
    return region_rate("middle-east")["base"]


def middle_east_per_kg():
    return region_rate("middle-east")["per_kg"]


def north_africa_base():
    return region_rate("north-africa")["base"]


def north_africa_per_kg():
    return region_rate("north-africa")["per_kg"]


def west_africa_base():
    return region_rate("west-africa")["base"]


def west_africa_per_kg():
    return region_rate("west-africa")["per_kg"]


def east_africa_base():
    return region_rate("east-africa")["base"]


def east_africa_per_kg():
    return region_rate("east-africa")["per_kg"]


def southern_africa_base():
    return region_rate("southern-africa")["base"]


def southern_africa_per_kg():
    return region_rate("southern-africa")["per_kg"]


def central_asia_base():
    return region_rate("central-asia")["base"]


def central_asia_per_kg():
    return region_rate("central-asia")["per_kg"]


def south_asia_base():
    return region_rate("south-asia")["base"]


def south_asia_per_kg():
    return region_rate("south-asia")["per_kg"]


def southeast_asia_base():
    return region_rate("southeast-asia")["base"]


def southeast_asia_per_kg():
    return region_rate("southeast-asia")["per_kg"]


def east_asia_base():
    return region_rate("east-asia")["base"]


def east_asia_per_kg():
    return region_rate("east-asia")["per_kg"]


def oceania_base():
    return region_rate("oceania")["base"]


def oceania_per_kg():
    return region_rate("oceania")["per_kg"]


def pacific_islands_base():
    return region_rate("pacific-islands")["base"]


def pacific_islands_per_kg():
    return region_rate("pacific-islands")["per_kg"]


def caribbean_base():
    return region_rate("caribbean")["base"]


def caribbean_per_kg():
    return region_rate("caribbean")["per_kg"]


def central_america_base():
    return region_rate("central-america")["base"]


def central_america_per_kg():
    return region_rate("central-america")["per_kg"]


def andes_base():
    return region_rate("andes")["base"]


def andes_per_kg():
    return region_rate("andes")["per_kg"]


def arctic_base():
    return region_rate("arctic")["base"]


def arctic_per_kg():
    return region_rate("arctic")["per_kg"]


def antarctic_base():
    return region_rate("antarctic")["base"]


def antarctic_per_kg():
    return region_rate("antarctic")["per_kg"]


def tier_index(weight_kg):
    for index, limit in enumerate(TIER_LIMITS_KG):
        if weight_kg < limit:
            return index
    return len(TIER_LIMITS_KG)


def tier_multiplier(weight_kg):
    return TIER_MULTIPLIERS[tier_index(weight_kg)]


def shipping_cost(region, weight_kg, level="standard"):
    rate = region_rate(region)
    rounded = round_up_to_half_kg(weight_kg)
    cost = rate["base"] + rate["per_kg"] * rounded * tier_multiplier(rounded)
    return round(cost * service_factor(level), 2)


def order_total(region, subtotal, weight_kg, level="standard"):
    if subtotal >= FREE_SHIPPING_THRESHOLD and not is_remote(region):
        return round(subtotal, 2)
    return round(subtotal + shipping_cost(region, weight_kg, level), 2)
