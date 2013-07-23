#include <ma.h>
#include "LuaEngine.h"
#include "MAHeaders.h"
#include <Wormhole/FileUtil.h>
#include <mastdlib.h>
#include <mavsprintf.h>

extern "C" void extractAllFilesIfChanged() {
	Wormhole::FileUtil* mFileUtil = new Wormhole::FileUtil();
	mFileUtil->extractLocalFiles();
	delete mFileUtil;
}

extern "C" int MAMain() {
	MobileLua::LuaEngine engine;
	if (!engine.initialize())
		return -1;
	extractAllFilesIfChanged();
	engine.eval(LUALIB);
	engine.eval(LUAFER);
	return 0;
}
