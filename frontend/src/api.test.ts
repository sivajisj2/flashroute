import{describe,it,expect}from'vitest';
import{units}from'./api';
describe('base unit conversion',()=>{it('preserves six decimals exactly',()=>{expect(units('100.123456')).toBe(100123456)});it('rejects malformed and out-of-policy amounts',()=>{for(const v of ['NaN','1e4','-100','100.1234567','0','100001'])expect(()=>units(v)).toThrow();});});
