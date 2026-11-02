import unittest

from pricing import TIER_MULTIPLIERS, shipping_cost, tier_index, tier_multiplier


class TierBoundaryTest(unittest.TestCase):
    def test_a_weight_at_a_tier_limit_stays_in_the_lower_tier(self):
        self.assertEqual(tier_index(1.0), 0)
        self.assertEqual(tier_index(5.0), 1)
        self.assertEqual(tier_index(20.0), 2)

    def test_a_weight_just_over_a_limit_moves_up(self):
        self.assertEqual(tier_index(1.5), 1)
        self.assertEqual(tier_index(5.5), 2)
        self.assertEqual(tier_index(20.5), 3)

    def test_multiplier_follows_the_tier(self):
        self.assertEqual(tier_multiplier(0.5), TIER_MULTIPLIERS[0])
        self.assertEqual(tier_multiplier(5.0), TIER_MULTIPLIERS[1])
        self.assertEqual(tier_multiplier(100.0), TIER_MULTIPLIERS[3])


class ShippingCostTest(unittest.TestCase):
    def test_one_kilogram_to_western_europe_is_a_tier_one_price(self):
        self.assertEqual(shipping_cost("western-europe", 1.0), 6.2)

    def test_express_applies_the_service_factor(self):
        self.assertEqual(shipping_cost("western-europe", 1.0, "express"), 10.85)


if __name__ == "__main__":
    unittest.main()
