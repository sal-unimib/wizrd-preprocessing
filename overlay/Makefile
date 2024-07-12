SRC := $(wildcard *.c)
EXE := $(SRC:%.c=%)

CFLAGS := -std=gnu99 -pedantic
LDFLAGS := -L..
LDLIBS := -lm

ifeq ($(DEBUG), 1)
    CFLAGS += -g -O0 -Wall -Werror -Wextra -DDEBUG
else
	CFLAGS += -O2 -march=native -DNDEBUG
endif

.PHONY: all clean

all: $(EXE)

./%.$(ARCH): ./%.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

clean:
	$(RM) $(EXE)