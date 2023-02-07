package;

#if sys
import sys.io.File;
import sys.FileSystem;
import sys.thread.Thread;
#end

import flixel.FlxG;
import haxe.io.Path;
import lime.app.Future;
import flixel.FlxState;
import flixel.FlxSprite;
import lime.app.Promise;
import openfl.text.Font;
import flash.media.Sound;
import flixel.math.FlxMath;
import openfl.utils.Assets;
import flixel.util.FlxTimer;
import transition.Transition;
import lime.utils.AssetLibrary;
import lime.utils.AssetManifest;
import openfl.display.BitmapData;
import flixel.graphics.FlxGraphic;
import transition.TransitionableState;
import lime.utils.Assets as LimeAssets;
import openfl.utils.Future as OpenFlFuture;

using StringTools;

class LoadingState extends TransitionableState
{
	var targetShit:Float = 0;

	#if web
	var callbacks:MultiCallback;
	#end

	var funkay:FlxSprite;
	var loadBar:FlxSprite;
	
	var target:FlxState;
	var stopMusic:Bool = false;
	var directory:String;

	function new(target:FlxState, stopMusic:Bool, directory:String):Void
	{
		super();

		this.target = target;
		this.stopMusic = stopMusic;
		this.directory = directory;
	}

	public static var loadedPaths:Map<String, Bool> = new Map<String, Bool>();

	var curFile:Int = 0;
	var filesToCheck:Array<String> = [];

	var extensions:Array<String> = [];

	public override function create():Void
	{
		extensions = ['.png', '.' + Paths.SOUND_EXT];

		var bg:FlxSprite = new FlxSprite();
		bg.makeGraphic(FlxG.width, FlxG.height, 0xFFCAFF4D);
		add(bg);

		funkay = new FlxSprite();
	
		if (Paths.fileExists('images/funkay.png', IMAGE))
			funkay.loadGraphic(Paths.getImage('funkay'));
		else
			funkay.loadGraphic(Paths.getImage('bg/funkay'));

		funkay.setGraphicSize(0, FlxG.height);
		funkay.updateHitbox();
		funkay.antialiasing = OptionData.globalAntialiasing;
		funkay.scrollFactor.set();
		funkay.screenCenter();
		add(funkay);

		loadBar = new FlxSprite(0, FlxG.height - 20);
		loadBar.makeGraphic(FlxG.width, 10, 0xFFFF16D2);
		loadBar.antialiasing = OptionData.globalAntialiasing;
		loadBar.screenCenter(X);
		loadBar.scale.x = 0.00001;
		add(loadBar);

		if (Transition.nextCamera != null) {
			Transition.nextCamera = null;
		}

		FlxG.camera.fade(FlxG.camera.bgColor, 0.5, true, function():Void
		{
			#if web
			initSongsManifest().onComplete(function(lib:AssetLibrary):Void
			{
				callbacks = new MultiCallback(onLoad);
			#end

				if (PlayState.SONG != null)
				{
					#if sys
					filesToCheck.push(getSongPath());

					if (PlayState.SONG.needsVoices) {
						filesToCheck.push(getVocalPath());
					}
					#else
					checkLoadSong(getSongPath());
					#end
				}

				checkLibrary('shared');

				if (directory != null && directory.length > 0 && directory != 'shared') {
					checkLibrary(directory);
				}

				#if sys
				new FlxTimer().start(1, function(_:FlxTimer):Void
				{
					Thread.create(function():Void {
						checkFile(filesToCheck[curFile]);
					});
				});
				#end

			#if web
				var introComplete:Void->Void = callbacks.add('introComplete');
				new FlxTimer().start(1.5, function(_:FlxTimer):Void introComplete());
			});
			#end
		});
	}

	#if web
	function checkLoadSong(path:String):Void
	{
		if (!Assets.cache.hasSound(path))
		{
			var callback:Void->Void = callbacks.add("song:" + path);

			Assets.loadSound(path).onComplete(function(sound:Sound):Void
			{
				Debug.logInfo('loaded path: ' + path);
				callback();

				if (PlayState.SONG != null && PlayState.SONG.needsVoices) {
					checkLoadSong(getVocalPath());
				}
			}).onError(function(_:Dynamic):Void
			{
				Debug.logWarn('path not found: ' + path);
				callback();
			});
		}
	}
	#end

	function checkLibrary(library:String):Void
	{
		#if web
		var callback:Void->Void = callbacks.add("library:" + library);

		#if NO_PRELOAD_ALL
		Debug.logInfo(Assets.hasLibrary(library));
		#end

		if (Assets.getLibrary(library) == null)
		{
			@:privateAccess
			if (!LimeAssets.libraryPaths.exists(library))
				throw "Missing library: " + library;

			Assets.loadLibrary(library).onComplete(function(library:AssetLibrary):Void {
				callback();
			});
		}
		#elseif sys
		var libraryPath:String = Paths.getPreloadPath(library);
		loadFolderForce(libraryPath);

		#if MODS_ALLOWED
		var modPath:String = 'mods';
		loadFolderForce(modPath);

		if (Paths.currentModDirectory != null && Paths.currentModDirectory.length > 0)
		{
			var modPath:String = Paths.mods(Paths.currentModDirectory);
			loadFolderForce(modPath);
		}

		for (mod in Paths.getGlobalMods())
		{
			var fileToCheck:String = Paths.mods(mod);
		
			if (FileSystem.exists(fileToCheck)) {
				loadFolderForce(modPath);
			}
		}
		#end
		#end
	}

	#if sys
	function loadFolderForce(pathFolder:String):Void
	{
		for (path in FileSystem.readDirectory(pathFolder))
		{
			var gottenPath:String = Path.join([pathFolder, path]);

			if (FileSystem.isDirectory(gottenPath)) {
				loadFolderForce(gottenPath);
			}
			else
			{
				if (!Paths.currentTrackedAssets.exists(gottenPath) && !Paths.currentTrackedSounds.exists(gottenPath)) {
					filesToCheck.push(gottenPath);
				}
			}
		}
	}

	function checkFile(path:String):Void
	{
		if (path.endsWith('.png'))
		{
			if (!Paths.currentTrackedAssets.exists(path) || !loadedPaths.exists(path))
			{
				BitmapData.loadFromFile(path).onComplete(function(bitmap:BitmapData):Void
				{
					var newGraphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, path);
					newGraphic.persist = true;

					loadedPaths.set(path, true);
					Paths.currentTrackedAssets.set(path, newGraphic);

					Debug.logInfo('loaded path: ' + path);
					onLoadComplete();
				}).onError(function(_:Dynamic):Void
				{
					Debug.logWarn('path not found: ' + path);
					onLoadComplete();
				});
			}
			else {
				onLoadComplete();
			}
		}

		if (path.endsWith('.${Paths.SOUND_EXT}'))
		{
			if (!Paths.currentTrackedSounds.exists(path) || !loadedPaths.exists(path))
			{
				Sound.loadFromFile(path).onComplete(function(sound:Sound):Void
				{
					Paths.currentTrackedSounds.set(path, sound);
					loadedPaths.set(path, true);

					Debug.logInfo('loaded path: ' + path);
					onLoadComplete();
				}).onError(function(_:Dynamic):Void
				{
					Debug.logWarn('path not found: ' + path);
					onLoadComplete();
				});
			}
			else {
				onLoadComplete();
			}
		}
	}

	function onLoadComplete():Void
	{
		curFile++;

		if (curFile < filesToCheck.length)
		{
			var ourFile:String = filesToCheck[curFile];

			if (ourFile.endsWith('.png') || ourFile.endsWith('.${Paths.SOUND_EXT}')) {
				checkFile(ourFile);
			}
			else {
				onLoadComplete();
			}
		}
		else {
			onLoad();
		}
	}
	#end

	public override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		var wacky:Float = FlxG.width * 0.88;

		funkay.setGraphicSize(Std.int(wacky + 0.9 * (funkay.width - wacky)));
		funkay.updateHitbox();

		if (controls.ACCEPT || FlxG.mouse.justPressed)
		{
			funkay.setGraphicSize(Std.int(funkay.width + 60));
			funkay.updateHitbox();

			#if (debug && web)
			if (callbacks != null) Debug.logInfo('fired: ' + callbacks.getFired() + " unfired:" + callbacks.getUnfired());
			#end
		}

		#if web
		if (callbacks != null)
		{
			targetShit = FlxMath.remapToRange(callbacks.numRemaining / callbacks.length, 1, 0, 0, 1);
			#else
			var length:Int = filesToCheck.length > 0 ? filesToCheck.length : 1;
			targetShit = FlxMath.remapToRange(curFile / length, 0, length, 0, length);
			#end

			loadBar.scale.x = CoolUtil.coolLerp(loadBar.scale.x, targetShit, 0.50); #if web
		}
		#end
	}
	
	function onLoad():Void
	{
		if (stopMusic && FlxG.sound.music != null)
		{
			FlxG.sound.music.stop();
			FlxG.sound.music.volume = 0;
		}

		FreeplayMenuState.destroyFreeplayVocals();
		FlxG.switchState(target);
	}

	static function getSongPath():String
	{
		return Paths.getInst(PlayState.SONG.songID, CoolUtil.getDifficultySuffix(PlayState.lastDifficulty), true);
	}

	static function getVocalPath():String
	{
		return Paths.getVoices(PlayState.SONG.songID, CoolUtil.getDifficultySuffix(PlayState.lastDifficulty), true);
	}

	public static function loadAndSwitchState(target:FlxState, stopMusic:Bool = false, skipLoading:Bool = false):Void
	{
		FlxG.switchState(getNextState(target, stopMusic, skipLoading));
	}
	
	static function getNextState(target:FlxState, stopMusic:Bool = false, skipLoading:Bool = false):FlxState
	{
		var directory:String = 'shared';
		var weekDir:String = StageData.forceNextDirectory;

		StageData.forceNextDirectory = null;

		if (weekDir != null && weekDir.length > 0 && weekDir != '') directory = weekDir;

		Paths.setCurrentLevel(directory);

		var loaded:Bool = false;

		if (OptionData.loadingScreen && !skipLoading)
		{
			if (PlayState.SONG != null) {
				loaded = isSoundLoaded(getSongPath()) && (!PlayState.SONG.needsVoices || isSoundLoaded(getVocalPath())) && isLibraryLoaded("shared") && isLibraryLoaded(directory);
			}

			if (!loaded) {
				return new LoadingState(target, stopMusic, directory);
			}
		}

		if (stopMusic && FlxG.sound.music != null)
		{
			FlxG.sound.music.stop();
			FlxG.sound.music.volume = 0;
		}

		FreeplayMenuState.destroyFreeplayVocals();
		return target;
	}

	static function isSoundLoaded(path:String):Bool
	{
		return #if sys Paths.currentTrackedSounds.exists(path) || loadedPaths.exists(path) #else Assets.cache.hasSound(path) #end;
	}
	
	static function isLibraryLoaded(library:String):Bool
	{
		return Assets.getLibrary(library) != null;
	}

	public override function destroy():Void
	{
		super.destroy();

		#if web
		callbacks = null;
		#end
	}
	
	static function initSongsManifest():Future<AssetLibrary>
	{
		var id:String = "songs";
		var promise:Promise<AssetLibrary> = new Promise<AssetLibrary>();

		var library:AssetLibrary = LimeAssets.getLibrary(id);

		if (library != null) {
			return Future.withValue(library);
		}

		var path:String = id;
		var rootPath:Null<String> = null;

		@:privateAccess
		var libraryPaths:Map<String, String> = LimeAssets.libraryPaths;
		if (libraryPaths.exists(id))
		{
			path = libraryPaths[id];
			rootPath = Path.directory(path);
		}
		else
		{
			if (StringTools.endsWith(path, ".bundle"))
			{
				rootPath = path;
				path += "/library.json";
			}
			else {
				rootPath = Path.directory(path);
			}
			@:privateAccess
			path = LimeAssets.__cacheBreak(path);
		}

		AssetManifest.loadFromFile(path, rootPath).onComplete(function(manifest:AssetManifest):Void
		{
			if (manifest == null)
			{
				promise.error("Cannot parse asset manifest for library \"" + id + "\"");
				return;
			}

			var library:AssetLibrary = AssetLibrary.fromManifest(manifest);

			if (library == null) {
				promise.error("Cannot open library \"" + id + "\"");
			}
			else
			{
				@:privateAccess
				LimeAssets.libraries.set(id, library);
				library.onChange.add(LimeAssets.onChange.dispatch);
				promise.completeWith(Future.withValue(library));
			}
		}).onError(function(_:Dynamic):Void {
			promise.error("There is no asset library with an ID of \"" + id + "\"");
		});

		return promise.future;
	}
}

#if web
class MultiCallback
{
	public var callback:Void->Void;
	public var logId:String = 'log';
	public var length(default, null) = 0;
	public var numRemaining(default, null) = 0;
	
	var unfired:Map<String, Void->Void> = new Map<String, Void->Void>();
	var fired:Array<String> = new Array<String>();
	
	public function new(callback:Void->Void, logId:String = 'log'):Void
	{
		this.callback = callback;
		this.logId = logId;
	}
	
	public function add(id:String = "untitled"):Void->Void
	{
		id = '$length:$id';

		length++;
		numRemaining++;

		var func:Void->Void = function():Void
		{
			if (unfired.exists(id))
			{
				unfired.remove(id);
				fired.push(id);
				numRemaining--;
				
				if (logId != null) {
					log('fired $id, $numRemaining remaining');
				}

				#if web
				if (numRemaining == 0)
				{
					if (logId != null) {
						log('all callbacks fired');
					}

					callback();
				}
				#end
			}
			else {
				log('already fired $id');
			}
		}

		unfired.set(id, func);
		return func;
	}
	
	inline function log(msg:String):Void
	{
		if (logId != null)
			Debug.logInfo('$logId: $msg');
	}
	
	public function getFired():Array<String> return fired.copy();
	public function getUnfired():Array<String> return [for (id in unfired.keys()) id];
}
#end