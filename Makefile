APP_NAME = build
BUILD_DIR = ./build


APP_INCLUDES:=
APP_LINKERS:=
APP_FRAMEWORKS:=
APP_FILES:= ./src/Core/*.m

SHADER_BUILD_DIR = ./src/Shaders/build
SHADER_INTER_FILES:= $(SHADER_BUILD_DIR)/*.ir
SHADER_FILES:= ./src/Shaders/*.metal


all: buildShader buildApp run


buildShader:
	xcrun -sdk macosx metal -o $(SHADER_BUILD_DIR)/shader.ir  -c $(SHADER_FILES)
	xcrun -sdk macosx metallib -o $(SHADER_BUILD_DIR)/shader.metallib $(SHADER_INTER_FILES)
	
buildApp:
	clang -fobjc-arc -fmodules -framework CoreGraphics -framework Metal -o $(BUILD_DIR)/$(APP_NAME) $(APP_FILES)

run: 
	$(BUILD_DIR)/$(APP_NAME)
