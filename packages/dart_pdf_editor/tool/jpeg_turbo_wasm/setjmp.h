typedef int jmp_buf[1];

extern int setjmp(jmp_buf);
extern void longjmp(jmp_buf, int);
