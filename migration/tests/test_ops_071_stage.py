import importlib.util, pathlib, unittest
P=pathlib.Path(__file__).resolve().parents[1]/'ops_071_stage.py'
spec=importlib.util.spec_from_file_location('ops071',P);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Ops071HelpersTest(unittest.TestCase):
 def test_packaging(self):
  self.assertEqual(m.parse_packaging('1.000 cái/ Thùng')['units_per_package'],1000)
  self.assertEqual(m.parse_packaging('5000 cái/ Bao')['package_name'],'Bao')
  self.assertIsNone(m.parse_packaging('500 cái'))
 def test_number(self):
  self.assertEqual(m.dec('1.000'),1000)
  self.assertEqual(m.dec('12,5'),m.Decimal('12.5'))
  self.assertIsNone(m.dec('#REF!'))
 def test_sku_is_deterministic(self):
  a=m.generated_sku('f','s',10,'Muỗng 15 cm','5000 cái/ Thùng')
  b=m.generated_sku('f','s',10,'Muỗng 15 cm','5000 cái/ Thùng')
  self.assertEqual(a,b);self.assertTrue(a.startswith('MIG-'))
 def test_status_dimensions(self):
  self.assertEqual(m.STATUS_MAP['CHỜ IN'],{'print':'WAITING'})
  self.assertEqual(m.STATUS_MAP['ĐÃ GIAO - CHƯA THU']['delivery'],'COMPLETED')
 def test_quarantine_contract(self):
  required={'REVIEW_PAYMENT_LINK','REVIEW_PRICE_BLOCK','REVIEW_OPENING_BALANCE','REVIEW_SPREADSHEET_ERROR'}
  self.assertTrue(required.issubset(m.QUARANTINE_CODES))
if __name__=='__main__':unittest.main()
