PREFIX ?= ..
CXX ?= g++
AR ?= ar
CXXFLAGS ?= -std=c++17 -O3 -DNDEBUG
CPPFLAGS ?= -Iinclude

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
	cp -a include/sdsl/*.hpp $(PREFIX)/include/sdsl/
	cp -a $(LIB) $(PREFIX)/lib/

clean:
	rm -f src/*.o lib/libsdsl.a

.PHONY: all install clean
