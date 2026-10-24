"""Optional local pricing APIs, independent coverage and live craft quantities."""
import unittest
from test_work_orders import fresh

CASES = {
'full_cost_and_outstanding_bag_shortfall_use_different_quantities': '''
 Auctioneer={Statistics=function(self,id)
  return {{Best=function() return id==7 and 200 or 100 end}}
 end}
 local p=addon.Pricing
 local entries={{itemID=7,recipeRequired=6,required=3,owned=1,bank=100},
 {itemID=8,recipeRequired=3,required=3,owned=5}}
 local r=p:Estimate(entries)
 assert(r.full==1500 and r.buy==400 and r.fullMissing==0 and r.buyMissing==0)
 assert(r.sources['Auctioneer statistics'] and entries[1].unitPrice==200)
 assert(p:Summary(r):find('To buy: 0g 4s 0c',1,true))
''',
'modern_and_legacy_tsm_have_correct_call_shapes_and_error_fallback': '''
 Auctioneer={Statistics=function() error('not ready') end}
 TSM_API={GetCustomPriceValue=function(key,item)
  assert(key=='dbmarket' and item=='i:7');return 456
 end}
 local value,source=addon.Pricing:UnitPrice(7)
 assert(value==456 and source=='TSM DBMarket')
 TSM_API.GetCustomPriceValue=function() return 0/0 end
 TSMAPI={GetItemValue=function(self,item,key)
  assert(self==TSMAPI and item=='item:7' and key=='DBMarket');return 789
 end}
 value,source=addon.Pricing:UnitPrice(7)
 assert(value==789 and source=='TSM DBMarket (legacy)')
''',
'partial_full_cost_does_not_make_a_complete_zero_shortfall_unknown': '''
 local r=addon.Pricing:Estimate({{itemID=7,recipeRequired=3,required=3,owned=10}})
 assert(r.fullMissing==1 and r.buyMissing==0 and r.buy==0 and r.bagUnknown==0)
 assert(addon.Pricing:Summary(r):find('To buy: 0g 0s 0c',1,true))
 r=addon.Pricing:Estimate({{itemID=7,recipeRequired=3,required=0}})
 assert(r.bagUnknown==0 and r.buy==0)
''',
'missing_prices_and_unknown_bags_never_look_like_complete_totals': '''
 TSM_API={GetCustomPriceValue=function(_,item) if item=='i:7' then return 100 end end}
 local r=addon.Pricing:Estimate({{itemID=7,recipeRequired=2,required=2,owned=0},
 {itemID=8,recipeRequired=4,required=4,owned=0}})
 assert(r.full==200 and r.buy==200 and r.fullMissing==1 and r.buyMissing==1)
 assert(addon.Pricing:Summary(r):find('+ ?',1,true))
 r=addon.Pricing:Estimate({{itemID=7,recipeRequired=2,required=2}})
 assert(r.full==200 and r.bagUnknown==1)
 assert(addon.Pricing:Summary(r):find('? (bag count)',1,true))
''',
'provider_failures_and_invalid_values_are_unavailable_not_free': '''
 for _,value in ipairs({0,-1,math.huge,0/0,'100'}) do
  TSM_API={GetCustomPriceValue=function() return value end}
  assert(not addon.Pricing:UnitPrice(7))
 end
 TSM_API={GetCustomPriceValue=function() error('provider error') end}
 local r=addon.Pricing:Estimate({{itemID=7,recipeRequired=1,required=1,owned=0}})
 assert(addon.Pricing:Summary(r)=='Prices unavailable')
 assert(not addon.Pricing:Estimate(nil))
''',
'auctioneer_statistics_preferred_and_broken_stat_does_not_block_next': '''
 Auctioneer={Statistics=function(self,id)
  assert(self==Auctioneer and id==7)
  return {{Best=function() error('missing stats') end},{Best=function() return 12.5 end}}
 end}
 TSM_API={GetCustomPriceValue=function() error('native stats should win') end}
 local r=addon.Pricing:Estimate({{itemID=7,recipeRequired=3,required=3,owned=1}})
 assert(r.full==37.5 and r.buy==25)
 assert(addon.Pricing:Money(r.full)=='0g 0s 38c')
''',
'cache_is_bounded_expires_and_detects_late_loaded_providers': '''
 local calls=0
 TSM_API={GetCustomPriceValue=function() calls=calls+1;return 100 end}
 local p=addon.Pricing
 p:UnitPrice(7);p:UnitPrice(7);assert(calls==1)
 clock=clock+31;p:UnitPrice(7);assert(calls==2)
 for id=1000,1140 do p:UnitPrice(id) end
 local before=calls;p:UnitPrice(7);assert(calls==before+1)
 p:Clear();p:UnitPrice(7);assert(calls==before+2)
 TSM_API=nil;p:UnitPrice(9)
 TSM_API={GetCustomPriceValue=function() return 333 end}
 assert(p:UnitPrice(9)==333)
''',
'price_panel_updates_for_quantity_bags_and_explicit_local_refresh': '''
 local price=100
 TSM_API={GetCustomPriceValue=function() return price end}
 inventoryFixture(false,true)
 addon.Directory:Toggle()
 addon.Directory.selectedRecipe={id=42,name='Potion',profession='Alchemy',crafters={}}
 addon.Directory:RefreshDetails()
 local view=addon.SelectedCraft
 assert(view.priceButton:IsShown() and view.priceEstimate.full==300 and view.priceEstimate.buy==0)
 addon.ShoppingList:SetQuantity(42,10);flushTimers()
 assert(view.priceEstimate.full==3000 and view.priceEstimate.buy==600)
 inventory[1].count=0;inventory[2].count=0;dispatch('BAG_UPDATE',0);flushTimers()
 assert(view.priceEstimate.buy==3000)
 price=200;view.priceButton.scripts.OnClick()
 assert(view.priceEstimate.full==6000 and view.priceEstimate.buy==6000)
''',
}

class PricingTests(unittest.TestCase):
    pass

for runtime in ('lua51', 'luajit21'):
    for profile in ('modern', 'legacy', 'minimal'):
        for name, code in CASES.items():
            def check(self, runtime=runtime, profile=profile, code=code):
                lua=fresh(runtime,profile)
                lua.execute(code)
            setattr(PricingTests,f'test_{runtime}_{profile}_{name}',check)
