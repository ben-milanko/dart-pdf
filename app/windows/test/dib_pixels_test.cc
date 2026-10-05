// Host-portable unit test for runner/dib_pixels.h (the clipboard DIB decode
// behind Windows image paste). Built and run by CI's linux job:
//   g++ -std=c++17 app/windows/test/dib_pixels_test.cc && ./a.out
#include "../runner/dib_pixels.h"
#undef NDEBUG
#include <cassert>
#include <cstdio>
#include <cstring>
using namespace dart_pdf;
static void put32(std::vector<uint8_t>& v, size_t at, uint32_t x){for(int i=0;i<4;i++)v[at+i]=(x>>(8*i))&255;}
// 2x2, bitfields with trailing masks (CF_DIB as Windows synthesizes it)
static std::vector<uint8_t> dib(int32_t h, bool bitfields, std::vector<uint8_t> rows){
  size_t off = 40 + (bitfields?12:0);
  std::vector<uint8_t> v(off + rows.size());
  put32(v,0,40); put32(v,4,2); put32(v,8,(uint32_t)h); v[12]=1; v[14]=32; put32(v,16,bitfields?3:0);
  if(bitfields){put32(v,40,0xFF0000);put32(v,44,0xFF00);put32(v,48,0xFF);}
  memcpy(v.data()+off, rows.data(), rows.size()); return v;
}
int main(){
  // bottom-up rows: stored row0 = bottom. Premultiplied: transparent bg + half-alpha red + opaque blue.
  std::vector<uint8_t> rows = {
    0,0,0,0,      0,0,128,128,   // bottom row: transparent, red@50% premul
    255,0,0,255,  0,0,0,0 };     // top row: opaque blue, transparent
  auto r = DecodePackedDib32(dib(2,true,rows).data(), dib(2,true,rows).size());
  assert(r && r->width==2 && r->height==2 && r->has_alpha);
  // top-down: first pixel opaque blue
  assert(r->bgra[0]==255 && r->bgra[3]==255);
  // bottom row second pixel: red unpremultiplied to 255, alpha 128
  assert(r->bgra[12+2]==255 && r->bgra[12+3]==128);
  assert(r->bgra[8+3]==0);
  // all-zero alpha -> opaque, colours untouched
  std::vector<uint8_t> opaque = {10,20,30,0, 40,50,60,0, 70,80,90,0, 1,2,3,0};
  auto o = DecodePackedDib32(dib(-2,false,opaque).data(), dib(-2,false,opaque).size());
  assert(o && !o->has_alpha && o->bgra[0]==10 && o->bgra[3]==255 && o->bgra[15]==255);
  // straight alpha (colour > alpha) untouched
  std::vector<uint8_t> straight = {0,0,255,128, 0,0,0,255, 0,0,0,255, 0,0,0,255};
  auto s = DecodePackedDib32(dib(-2,false,straight).data(), dib(-2,false,straight).size());
  assert(s && s->has_alpha && s->bgra[2]==255 && s->bgra[3]==128);
  // non-standard masks / truncated rejected
  auto bad = dib(2,true,rows); put32(bad,40,0xFF);
  assert(!DecodePackedDib32(bad.data(), bad.size()));
  auto trunc = dib(2,true,rows);
  assert(!DecodePackedDib32(trunc.data(), trunc.size()-1));
  assert(!DecodePackedDib32(nullptr, 0));
  puts("ok");
}
