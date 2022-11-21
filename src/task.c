#define M 64
#define N 60
#define K 32
int8 a[M][K];
int16 b[K][N];
int32 c[M][N];
 
void mmul() {
  int8 *pa = a;
  int32 *pc = c;
  for (int y = 0; y < M; y++) {
    for (int x = 0; x < N; x++) {
      int16 *pb = b;
      int32 s = 0;
      for (int k = 0; k < K; k++) {
        s += pa[k] * pb[x];
        pb += N;
      }
      pc[x] = s;
    }
    pa += K;
    pc += N;
  }
}
