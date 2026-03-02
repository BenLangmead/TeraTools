PREFIX ?= ..
CXX ?= g++
AR ?= ar
CXXFLAGS ?= -std=c++17 -O3 -DNDEBUG

LOCAL_INCLUDE_ROOT := include
INTEGRATED_INCLUDE_ROOT := ../include

ifeq ($(wildcard $(LOCAL_INCLUDE_ROOT)/sdsl/bits.hpp),)
HEADER_SOURCE_ROOT := $(INTEGRATED_INCLUDE_ROOT)
else
HEADER_SOURCE_ROOT := $(LOCAL_INCLUDE_ROOT)
endif

CPPFLAGS ?= -I$(LOCAL_INCLUDE_ROOT) -I$(HEADER_SOURCE_ROOT)

SOURCES := $(wildcard src/*.cpp)
OBJECTS := $(SOURCES:.cpp=.o)
LIB := lib/libsdsl.a

all: $(LIB)

$(LIB): $(OBJECTS)
	@mkdir -p lib
	$(AR) rcs $@ $^

src/%.o: src/%.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

install: $(LIB)
	mkdir -p $(PREFIX)/include/sdsl $(PREFIX)/lib
	if [ "$(abspath $(HEADER_SOURCE_ROOT))" != "$(abspath $(PREFIX)/include)" ]; then cp -a $(HEADER_SOURCE_ROOT)/sdsl/*.hpp $(PREFIX)/include/sdsl/; fi
	if [ -d $(LOCAL_INCLUDE_ROOT)/sdsl ]; then cp -a $(LOCAL_INCLUDE_ROOT)/sdsl/*.hpp $(PREFIX)/include/sdsl/; fi
	cp -a $(LIB) $(PREFIX)/lib/

clean:
	rm -f src/*.o lib/libsdsl.a

.PHONY: all install clean
