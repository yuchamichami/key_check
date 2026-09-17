const {test} = require('node:test');
const assert = require('node:assert/strict');
const {resolve} = require('../docs/keyboard-input.js');
const codes = {Lang1:1,Lang2:1,Lang3:1,Lang4:1,Lang5:1,Convert:1,NonConvert:1,KeyA:1};
test('physical code wins over IME-generated key and legacy 229', () => {
  for (const code of Object.keys(codes)) assert.equal(resolve({code,key:'Process',keyCode:229},codes,true),code);
});
test('Japanese key names work when code is missing', () => {
  for (const [key,expected] of [['Eisu','Lang2'],['Alphanumeric','Lang2'],['KanjiMode','Lang1'],['Hiragana','Lang4'],['Katakana','Lang3'],['Convert','Convert'],['NonConvert','NonConvert']]) {
    assert.equal(resolve({code:'',key},codes,true),expected);
  }
});
test('unknown IME events never invent an eisuu/kana press', () => {
  assert.equal(resolve({code:'',key:'Process',keyCode:229},codes,true),'Process');
  assert.equal(resolve({code:'Unidentified',key:'Unidentified',keyCode:229},codes,true),'Unidentified');
  assert.equal(resolve({code:'',key:'KanjiMode'},codes,false),'KanjiMode');
});
test('legacy conversion codes are recognized without overriding real physical codes', () => {
  assert.equal(resolve({code:'',keyCode:28},codes),'Convert');
  assert.equal(resolve({code:'',keyCode:29},codes),'NonConvert');
  assert.equal(resolve({code:'KeyA',keyCode:28},codes),'KeyA');
});
