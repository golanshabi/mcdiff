APP_NAME := mcdiff
CLI_NAME := mcdiff
CLI := Scripts/$(CLI_NAME)
APP := build/$(APP_NAME).app
BIN := $(APP)/Contents/MacOS/$(APP_NAME)
LIBGIT2 ?= /opt/homebrew/opt/libgit2
CXX := clang++
CXXFLAGS := -std=c++17 -I$(LIBGIT2)/include
LDFLAGS := -L$(LIBGIT2)/lib -Wl,-rpath,$(LIBGIT2)/lib
SWIFT_LDFLAGS := -L$(LIBGIT2)/lib -Xlinker -rpath -Xlinker $(LIBGIT2)/lib
TEST_BIN := build/CoreTests
SWIFT_TEST_BIN := build/SwiftTests

build/.dir:
	mkdir -p build
	touch build/.dir

$(BIN): App/*.swift Bridge/* Core/* | build/.dir
	mkdir -p $(APP)/Contents/MacOS
	printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>$(APP_NAME)</string><key>CFBundleIdentifier</key><string>local.$(APP_NAME)</string><key>CFBundleName</key><string>$(APP_NAME)</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>' > $(APP)/Contents/Info.plist
	$(CXX) $(CXXFLAGS) -c Core/Logger.cpp -o build/Logger.o
	$(CXX) $(CXXFLAGS) -c Core/DiffEngine.cpp -o build/DiffEngine.o
	$(CXX) $(CXXFLAGS) -c Core/MergeBuilder.cpp -o build/MergeBuilder.o
	$(CXX) $(CXXFLAGS) -c Bridge/DiffBridge.mm -o build/DiffBridge.o
	swiftc App/*.swift build/Logger.o build/DiffEngine.o build/MergeBuilder.o build/DiffBridge.o -module-cache-path build/ModuleCache -import-objc-header Bridge/DiffBridge.h -framework AppKit $(SWIFT_LDFLAGS) -lgit2 -lc++ -o $(BIN)

build: $(BIN)

run: build
	open $(APP)

launcher:
	@echo "$(CLI)"

$(TEST_BIN): Tests/CoreTests.cpp Core/* | build/.dir
	$(CXX) $(CXXFLAGS) Tests/CoreTests.cpp Core/Logger.cpp Core/DiffEngine.cpp Core/MergeBuilder.cpp $(LDFLAGS) -lgit2 -o $(TEST_BIN)

$(SWIFT_TEST_BIN): Tests/SwiftTests.swift App/Logger.swift App/MainWindowController.swift Bridge/* Core/* | build/.dir
	$(CXX) $(CXXFLAGS) -c Core/Logger.cpp -o build/SwiftTestLogger.o
	$(CXX) $(CXXFLAGS) -c Core/DiffEngine.cpp -o build/SwiftTestDiffEngine.o
	$(CXX) $(CXXFLAGS) -c Core/MergeBuilder.cpp -o build/SwiftTestMergeBuilder.o
	$(CXX) $(CXXFLAGS) -c Bridge/DiffBridge.mm -o build/SwiftTestDiffBridge.o
	swiftc Tests/SwiftTests.swift App/Logger.swift App/MainWindowController.swift build/SwiftTest*.o -module-cache-path build/ModuleCache -import-objc-header Bridge/DiffBridge.h -framework AppKit $(SWIFT_LDFLAGS) -lgit2 -lc++ -o $(SWIFT_TEST_BIN)

test: $(TEST_BIN) $(SWIFT_TEST_BIN)
	$(TEST_BIN)
	$(SWIFT_TEST_BIN)

clean:
	rm -rf build

.PHONY: build run launcher test clean
