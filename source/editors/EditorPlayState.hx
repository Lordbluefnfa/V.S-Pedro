package editors;

import Song;
import Section;
import StageData;
import FunkinLua;
import PhillyGlow;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.math.FlxRect;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxSort;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.tweens.FlxEase;
import flixel.group.FlxGroup;
import flixel.system.FlxSound;
import flixel.tweens.FlxTween;
import openfl.events.KeyboardEvent;
import flixel.input.keyboard.FlxKey;
import openfl.utils.Assets as OpenFlAssets;

using StringTools;

class EditorPlayState extends MusicBeatState
{
	public static var instance:EditorPlayState = null;

	var generatedMusic:Bool = false;
	var vocals:FlxSound;

	var timerToStart:Float = 0;
	var startOffset:Float = 0;
	var startPos:Float = 0;
	var combo:Int = 0;

	public function new(startPos:Float):Void
	{
		super();

		this.startPos = startPos;

		Conductor.songPosition = startPos - startOffset;

		startOffset = Conductor.crochet;
		timerToStart = startOffset;
	}

	public var notes:FlxTypedGroup<Note>;
	public var unspawnNotes:Array<Note> = [];

	public var strumLine:FlxSprite;

	public var opponentStrums:FlxTypedGroup<StrumNote>;
	public var playerStrums:FlxTypedGroup<StrumNote>;
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash>;

	var grpRatings:FlxTypedGroup<Rating>;
	var grpNumbers:FlxTypedGroup<Number>;

	public var ratingTweensArray:Array<FlxTween> = [];
	public var numbersTweensArray:Array<FlxTween> = [];

	var scoreTxt:FlxText;
	var stepTxt:FlxText;
	var beatTxt:FlxText;
	var sectionTxt:FlxText;

	var songHits:Int = 0;
	var songMisses:Int = 0;

	private var keysArray:Array<Dynamic>;

	private var noteTypeMap:Map<String, Bool> = new Map<String, Bool>();

	public override function create():Void
	{
		super.create();

		instance = this;

		keysArray = [
			OptionData.copyKey(OptionData.keyBinds.get('note_left')),
			OptionData.copyKey(OptionData.keyBinds.get('note_down')),
			OptionData.copyKey(OptionData.keyBinds.get('note_up')),
			OptionData.copyKey(OptionData.keyBinds.get('note_right'))
		];

		var bg:FlxSprite = new FlxSprite();
		if (Paths.fileExists('images/menuDesat.png', IMAGE)) {
			bg.loadGraphic(Paths.getImage('menuDesat'));
		}
		else {
			bg.loadGraphic(Paths.getImage('bg/menuDesat'));
		}
		bg.scrollFactor.set();
		bg.color = FlxColor.fromHSB(FlxG.random.int(0, 359), FlxG.random.float(0, 0.8), FlxG.random.float(0.3, 1));
		add(bg);

		strumLine = new FlxSprite(OptionData.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X, OptionData.downScroll ? FlxG.height - 150 : 50);
		strumLine.makeGraphic(FlxG.width, 10);
		strumLine.scrollFactor.set();
		strumLine.alpha = 0;
		strumLine.visible = false;
		add(strumLine);

		opponentStrums = new FlxTypedGroup<StrumNote>();
		add(opponentStrums);

		playerStrums = new FlxTypedGroup<StrumNote>();
		add(playerStrums);

		grpNoteSplashes = new FlxTypedGroup<NoteSplash>();
		add(grpNoteSplashes);

		var splash:NoteSplash = new NoteSplash(100, 100, 0);
		splash.alpha = 0.0;
		grpNoteSplashes.add(splash);

		if (!OptionData.controllerMode)
		{
			FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
			FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
		}

		generateStaticArrows(0);
		generateStaticArrows(1);

		grpRatings = new FlxTypedGroup<Rating>();
		add(grpRatings);

		grpNumbers = new FlxTypedGroup<Number>();
		add(grpNumbers);

		if (PlayState.SONG.needsVoices)
			vocals = new FlxSound().loadEmbedded(Paths.getVoices(PlayState.SONG.songID, PlayState.lastDifficulty), #if NO_PRELOAD_ALL true #else false #end);
		else
			vocals = new FlxSound();

		generateSong(PlayState.SONG);

		#if LUA_ALLOWED
		for (notetype in noteTypeMap.keys())
		{
			#if MODS_ALLOWED
			var luaToLoad:String = Paths.modFolders('custom_notetypes/' + notetype + '.lua');

			if (FileSystem.exists(luaToLoad))
			{
				var lua:EditorLua = new EditorLua(luaToLoad);

				new FlxTimer().start(0.1, function(tmr:FlxTimer):Void
				{
					if (lua != null)
					{
						lua.stop();
						lua = null;
					}
				});
			}
			else
			{
				luaToLoad = Paths.getPreloadPath('custom_notetypes/' + notetype + '.lua');

				if (FileSystem.exists(luaToLoad))
				{
					var lua:EditorLua = new EditorLua(luaToLoad);

					new FlxTimer().start(0.1, function(tmr:FlxTimer):Void
					{
						if (lua != null)
						{
							lua.stop();
							lua = null;
						}
					});
				}
			}
			#elseif sys
			var luaToLoad:String = Paths.getPreloadPath('custom_notetypes/' + notetype + '.lua');

			if (OpenFlAssets.exists(luaToLoad))
			{
				var lua:EditorLua = new EditorLua(luaToLoad);

				new FlxTimer().start(0.1, function(tmr:FlxTimer):Void
				{
					if (lua != null)
					{
						lua.stop();
						lua = null;
					}
				});
			}
			#end
		}
		#end

		noteTypeMap.clear();
		noteTypeMap = null;

		scoreTxt = new FlxText(0, FlxG.height - 50, FlxG.width, "Hits: 0 | Combo Breaks: 0", 20);
		scoreTxt.setFormat(Paths.getFont('vcr.ttf'), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreTxt.scrollFactor.set();
		scoreTxt.borderSize = 1.25;
		scoreTxt.visible = OptionData.scoreText;
		add(scoreTxt);
		
		sectionTxt = new FlxText(10, 580, FlxG.width - 20, "Section: 0", 20);
		sectionTxt.setFormat(Paths.getFont('vcr.ttf'), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		sectionTxt.scrollFactor.set();
		sectionTxt.borderSize = 1.25;
		add(sectionTxt);
		
		beatTxt = new FlxText(10, sectionTxt.y + 30, FlxG.width - 20, "Beat: 0", 20);
		beatTxt.setFormat(Paths.getFont('vcr.ttf'), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		beatTxt.scrollFactor.set();
		beatTxt.borderSize = 1.25;
		add(beatTxt);

		stepTxt = new FlxText(10, beatTxt.y + 30, FlxG.width - 20, "Step: 0", 20);
		stepTxt.setFormat(Paths.getFont('vcr.ttf'), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		stepTxt.scrollFactor.set();
		stepTxt.borderSize = 1.25;
		add(stepTxt);

		var tipText:FlxText = new FlxText(10, FlxG.height - 24, 0, 'Press ESC to Go Back to Chart Editor', 16);
		tipText.setFormat(Paths.getFont('vcr.ttf'), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		tipText.borderSize = 2;
		tipText.scrollFactor.set();
		add(tipText);

		notes.forEachAlive(function(note:Note):Void
		{
			if (OptionData.opponentStrumsType != 'Disabled' || note.mustPress)
			{
				note.copyAlpha = false;
				note.alpha = note.multAlpha;

				if (OptionData.middleScroll == true && !note.mustPress) {
					note.alpha *= 0.35;
				}
			}
		});
	}

	private function generateSong(songData:SwagSong):Void
	{
		Conductor.changeBPM(songData.bpm);

		FlxG.sound.playMusic(Paths.getInst(songData.songID, PlayState.lastDifficulty), 0, #if NO_PRELOAD_ALL true #else false #end);
		FlxG.sound.music.pause();
		FlxG.sound.music.onComplete = endSong;
		vocals.pause();
		vocals.volume = 0;

		notes = new FlxTypedGroup<Note>();
		add(notes);

		var noteData:Array<SwagSection> = songData.notes;

		for (section in noteData)
		{
			for (songNotes in section.sectionNotes)
			{
				var daStrumTime:Float = songNotes[0];
				var daNoteData:Int = Std.int(songNotes[1] % 4);

				var gottaHitNote:Bool = section.mustHitSection;

				if (songNotes[1] > 3) {
					gottaHitNote = !section.mustHitSection;
				}

				var oldNote:Note = null;

				if (unspawnNotes.length > 0) {
					oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];
				}

				var swagNote:Note = new Note(daStrumTime, daNoteData, oldNote, false, false, gottaHitNote);
				swagNote.mustPress = gottaHitNote;
				swagNote.sustainLength = songNotes[2];
				swagNote.gfNote = (section.gfSection && (songNotes[1] < 4));
				swagNote.noteType = (!Std.isOfType(songNotes[3], String) ? editors.ChartingState.noteTypeList[songNotes[3]] : songNotes[3]);
				swagNote.scrollFactor.set();

				var susLength:Float = swagNote.sustainLength;

				susLength = susLength / Conductor.stepCrochet;
				unspawnNotes.push(swagNote);

				var floorSus:Int = Math.floor(susLength);

				if (floorSus > 0)
				{
					for (susNote in 0...floorSus + 1)
					{
						oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];

						var sustainNote:Note = new Note(daStrumTime + (Conductor.stepCrochet * susNote) + (Conductor.stepCrochet / FlxMath.roundDecimal(PlayState.SONG.speed, 2)), daNoteData, oldNote, true, false, gottaHitNote);
						sustainNote.mustPress = gottaHitNote;
						sustainNote.gfNote = (section.gfSection && (songNotes[1] < 4));
						sustainNote.noteType = swagNote.noteType;
						sustainNote.scrollFactor.set();
						swagNote.tail.push(sustainNote);
						sustainNote.parent = swagNote;
						unspawnNotes.push(sustainNote);

						if (sustainNote.mustPress) {
							sustainNote.x += FlxG.width / 2; // general offset
						}
						else if (OptionData.middleScroll)
						{
							sustainNote.x += 310;
		
							if (daNoteData > 1) { // Up and Right
								sustainNote.x += FlxG.width / 2 + 25;
							}
						}
					}
				}

				if (swagNote.mustPress) {
					swagNote.x += FlxG.width / 2; // general offset
				}
				else if (OptionData.middleScroll)
				{
					swagNote.x += 310;

					if (daNoteData > 1) { // Up and Right
						swagNote.x += FlxG.width / 2 + 25;
					}
				}

				if (!noteTypeMap.exists(swagNote.noteType)) {
					noteTypeMap.set(swagNote.noteType, true);
				}
			}
		}

		unspawnNotes.sort(sortByShit);

		generatedMusic = true;
	}

	function sortByShit(Obj1:Note, Obj2:Note):Int
	{
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);
	}

	private function generateStaticArrows(player:Int):Void
	{
		for (i in 0...4)
		{
			var targetAlpha:Float = 1;

			if (player == 0)
			{
				if (OptionData.opponentStrumsType == 'Disabled') {
					targetAlpha = 0;
				}
				else if (OptionData.middleScroll) {
					targetAlpha = 0.35;
				}
			}

			var babyArrow:StrumNote = new StrumNote(OptionData.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X, strumLine.y, i, player);
			babyArrow.downScroll = OptionData.downScroll;

			switch (player)
			{
				case 0:
				{
					if (OptionData.middleScroll)
					{
						babyArrow.x += 310;
	
						if (i > 1) { // Up and Right
							babyArrow.x += FlxG.width / 2 + 25;
						}
					}

					opponentStrums.add(babyArrow);
				}
				case 1:
				{
					playerStrums.add(babyArrow);
				}
			}

			babyArrow.postAddedToGroup();
		}
	}

	var startingSong:Bool = true;

	function startSong():Void
	{
		startingSong = false;

		FlxG.sound.music.time = startPos;
		FlxG.sound.music.volume = 1;
		FlxG.sound.music.play();

		vocals.time = startPos;
		vocals.volume = 1;
		vocals.play();
	}

	public var noteKillOffset:Float = 350;
	public var spawnTime:Float = 2000;

	public override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (FlxG.keys.justPressed.ESCAPE)
		{
			FlxG.sound.music.pause();
			vocals.pause();

			LoadingState.loadAndSwitchState(new ChartingState());
		}

		if (startingSong)
		{
			timerToStart -= elapsed * 1000;
			Conductor.songPosition = startPos - timerToStart;

			if (timerToStart < 0) {
				startSong();
			}
		}
		else
		{
			Conductor.songPosition += elapsed * 1000;
		}

		if (unspawnNotes[0] != null)
		{
			var time:Float = spawnTime;

			if (PlayState.SONG.speed < 1) time /= PlayState.SONG.speed;
			if (unspawnNotes[0].multSpeed < 1) time /= unspawnNotes[0].multSpeed;

			while (unspawnNotes.length > 0 && unspawnNotes[0].strumTime - Conductor.songPosition < time)
			{
				var dunceNote:Note = unspawnNotes[0];
				notes.insert(0, dunceNote);
				dunceNote.spawned = true;

				var index:Int = unspawnNotes.indexOf(dunceNote);
				unspawnNotes.splice(index, 1);
			}
		}

		if (generatedMusic)
		{
			notes.forEachAlive(function(daNote:Note):Void
			{
				var strumGroup:FlxTypedGroup<StrumNote> = daNote.mustPress ? playerStrums : opponentStrums;

				var strumX:Float = strumGroup.members[daNote.noteData].x;
				var strumY:Float = strumGroup.members[daNote.noteData].y;
	
				var strumAngle:Float = strumGroup.members[daNote.noteData].angle;
				var strumDirection:Float = strumGroup.members[daNote.noteData].direction;
	
				var strumAlpha:Float = strumGroup.members[daNote.noteData].alpha;
				var strumScroll:Bool = strumGroup.members[daNote.noteData].downScroll;

				strumX += daNote.offsetX;
				strumY += daNote.offsetY;

				strumAngle += daNote.offsetAngle;
				strumAlpha *= daNote.multAlpha;

				if (strumScroll) {
					daNote.distance = (0.45 * (Conductor.songPosition - daNote.strumTime) * PlayState.SONG.speed * daNote.multSpeed);
				}
				else {
					daNote.distance = (-0.45 * (Conductor.songPosition - daNote.strumTime) * PlayState.SONG.speed * daNote.multSpeed);
				}

				var angleDir:Float = strumDirection * Math.PI / 180;
	
				if (daNote.copyAngle) {
					daNote.angle = strumDirection - 90 + strumAngle;
				}

				if (daNote.copyAlpha) {
					daNote.alpha = strumAlpha;
				}

				if (daNote.copyX) {
					daNote.x = strumX + Math.cos(angleDir) * daNote.distance;
				}

				noteMovement(daNote, strumGroup, strumY + Note.swagWidth / 2, strumY, ((60 / PlayState.SONG.bpm) * 1000), angleDir, strumScroll);

				if (!daNote.mustPress && daNote.wasGoodHit && !daNote.hitByOpponent && !daNote.ignoreNote) {
					opponentNoteHit(daNote);
				}

				if (Conductor.songPosition > (noteKillOffset / PlayState.SONG.speed) + daNote.strumTime)
				{
					if (daNote.mustPress && !daNote.ignoreNote && (daNote.tooLate || !daNote.wasGoodHit)) {
						noteMiss(daNote);
					}

					daNote.active = false;
					daNote.visible = false;

					daNote.kill();
					notes.remove(daNote, true);
					daNote.destroy();
				}
			});
		}

		keyShit();

		scoreTxt.text = 'Hits: ' + songHits + ' | Combo Breaks: ' + songMisses;
		sectionTxt.text = 'Section: ' + curSection;
		beatTxt.text = 'Beat: ' + curBeat;
		stepTxt.text = 'Step: ' + curStep;
	}

	public override function openSubState(BaseSubState:FlxSubState):Void
	{
		super.openSubState(BaseSubState);

		for (tween in ratingTweensArray) {
			tween.active = false;
		}

		for (tween in numbersTweensArray) {
			tween.active = false;
		}
	}

	public override function closeSubState():Void
	{
		super.closeSubState();

		for (tween in ratingTweensArray) {
			tween.active = true;
		}

		for (tween in numbersTweensArray) {
			tween.active = true;
		}
	}

	private function noteMovement(daNote:Note, strumGroup:FlxTypedGroup<StrumNote>, center:Float, strumY:Float, fakeCrochet:Float, angleDir:Float, strumScroll:Bool):Void
	{
		if (daNote.copyY)
		{
			daNote.y = strumY + Math.sin(angleDir) * daNote.distance;

			if (strumScroll && daNote.isSustainNote) // Jesus fuck this took me so much mother fucking time AAAAAAAAAA
			{
				if (daNote.animation.curAnim.name.endsWith('end'))
				{
					daNote.y += 10.5 * (fakeCrochet / 400) * 1.5 * PlayState.SONG.speed + (46 * (PlayState.SONG.speed - 1));
					daNote.y -= 46 * (1 - (fakeCrochet / 600)) * PlayState.SONG.speed;
	
					if (PlayState.isPixelStage) {
						daNote.y += 8 + (6 - daNote.originalHeightForCalcs) * PlayState.daPixelZoom;
					}
					else {
						daNote.y -= 19;
					}
				}

				daNote.y += (Note.swagWidth / 2) - (60.5 * (PlayState.SONG.speed - 1));
				daNote.y += 27.5 * ((PlayState.SONG.bpm / 100) - 1) * (PlayState.SONG.speed - 1);
			}
		}

		switch (OptionData.sustainsType)
		{
			case 'Old':
			{
				if (daNote.y > FlxG.height)
				{
					daNote.active = false;
					daNote.visible = false;
				}
				else
				{
					daNote.visible = true;
					daNote.active = true;
				}
			}
			case 'New':
			{
				if (strumGroup.members[daNote.noteData].sustainReduce && daNote.isSustainNote && (daNote.mustPress || !daNote.ignoreNote) &&
					(!daNote.mustPress || (daNote.wasGoodHit || (daNote.prevNote.wasGoodHit && !daNote.canBeHit))))
				{
					if (strumScroll)
					{
						if (daNote.y - daNote.offset.y * daNote.scale.y + daNote.height >= center)
						{
							var swagRect:FlxRect = new FlxRect(0, 0, daNote.frameWidth, daNote.frameHeight);
							swagRect.height = (center - daNote.y) / daNote.scale.y;
							swagRect.y = daNote.frameHeight - swagRect.height;
		
							daNote.clipRect = swagRect;
						}
					}
					else
					{
						if (daNote.y + daNote.offset.y * daNote.scale.y <= center)
						{
							var swagRect:FlxRect = new FlxRect(0, 0, daNote.width / daNote.scale.x, daNote.height / daNote.scale.y);
							swagRect.y = (center - daNote.y) / daNote.scale.y;
							swagRect.height -= swagRect.y;
		
							daNote.clipRect = swagRect;
						}
					}
				}
			}
		}
	}

	private function popUpScore(daNote:Note):Void
	{
		var noteDiff:Float = Math.abs(daNote.strumTime - Conductor.songPosition + OptionData.ratingOffset);
		var placement:String = Std.string(combo);

		var coolText:FlxText = new FlxText(0, 0, 0, placement, 32);
		coolText.screenCenter();
		coolText.x = FlxG.width * 0.55;

		vocals.volume = 1;

		var daRating:String = Conductor.judgeNote(daNote, noteDiff, true);

		if (daRating == 'sick' && daNote != null && daNote.quickNoteSplash && !daNote.noteSplashDisabled && !daNote.isSustainNote) {
			spawnNoteSplashOnNote(daNote);
		}

		if (!daNote.isSustainNote)
		{
			songHits++;
			combo++;

			var rating:Rating = new Rating(daRating, (PlayState.isPixelStage ? '-pixel' : ''), coolText);
			grpRatings.add(rating);

			var seperatedScore:Array<Int> = [];

			seperatedScore.push(Math.floor(combo / 100));
			seperatedScore.push(Math.floor((combo - (seperatedScore[0] * 100)) / 10));
			seperatedScore.push(combo % 10);

			var daLoop:Int = 0;

			for (i in seperatedScore)
			{
				var numScore:Number = new Number(Std.int(i), (PlayState.isPixelStage ? '-pixel' : ''), coolText, daLoop);

				if (combo >= 10) {
					grpNumbers.add(numScore);
				}

				var numtwn = FlxTween.tween(numScore, {alpha: 0}, 0.2, {startDelay: Conductor.crochet * 0.002, onComplete: function(tween:FlxTween):Void
				{
					numbersTweensArray.remove(tween);

					numScore.kill();
					grpNumbers.remove(numScore, true);
					numScore.destroy();
				}});

				numbersTweensArray.push(numtwn);

				daLoop++;
			}

			coolText.text = Std.string(seperatedScore);

			var rttwn = FlxTween.tween(rating, {alpha: 0}, 0.2,
			{
				startDelay: Conductor.crochet * 0.001,
				onComplete: function(tween:FlxTween):Void
				{
					coolText.destroy();

					ratingTweensArray.remove(tween);

					rating.kill();
					grpRatings.remove(rating, true);
					rating.destroy();
				}
			});

			ratingTweensArray.push(rttwn);
		}
	}

	private function onKeyPress(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(eventKey);

		if (key > -1 && (FlxG.keys.checkStatus(eventKey, JUST_PRESSED) || OptionData.controllerMode))
		{
			if (generatedMusic)
			{
				var lastTime:Float = Conductor.songPosition;
				Conductor.songPosition = FlxG.sound.music.time;

				var pressNotes:Array<Note> = [];
				var notesStopped:Bool = false;

				var sortedNotesList:Array<Note> = [];

				notes.forEachAlive(function(daNote:Note):Void
				{
					if (daNote.canBeHit && daNote.mustPress && !daNote.tooLate && !daNote.wasGoodHit && !daNote.isSustainNote && daNote.noteData == key) {
						sortedNotesList.push(daNote);
					}
				});

				sortedNotesList.sort(sortHitNotes);

				if (sortedNotesList.length > 0)
				{
					for (epicNote in sortedNotesList)
					{
						for (doubleNote in pressNotes) 
						{
							if (Math.abs(doubleNote.strumTime - epicNote.strumTime) < 1)
							{
								doubleNote.kill();
								notes.remove(doubleNote, true);
								doubleNote.destroy();
							}
							else {
								notesStopped = true;
							}
						}

						if (!notesStopped) // eee jack detection before was not super good
						{
							goodNoteHit(epicNote);
							pressNotes.push(epicNote);
						}
					}
				}
				else
				{
					if (OptionData.ghostTapping == false) {
						noteMissPress(key);
					}
				}

				Conductor.songPosition = lastTime;
			}

			var spr:StrumNote = playerStrums.members[key];

			if (spr != null && spr.animation.curAnim.name != 'confirm')
			{
				spr.playAnim('pressed');
				spr.resetAnim = 0;
			}
		}
	}

	function sortHitNotes(a:Note, b:Note):Int
	{
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;

		return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	private function onKeyRelease(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(eventKey);

		if (key > -1)
		{
			var spr:StrumNote = playerStrums.members[key];

			if (spr != null)
			{
				spr.playAnim('static');
				spr.resetAnim = 0;
			}
		}
	}

	private function getKeyFromEvent(key:FlxKey):Int
	{
		if (key != NONE)
		{
			for (i in 0...keysArray.length)
			{
				for (j in 0...keysArray[i].length)
				{
					if (key == keysArray[i][j]) {
						return i;
					}
				}
			}
		}

		return -1;
	}

	private function keyShit():Void
	{
		var holdingArray:Array<Bool> = [controls.NOTE_LEFT, controls.NOTE_DOWN, controls.NOTE_UP, controls.NOTE_RIGHT];

		if (OptionData.controllerMode)
		{
			var controlArray:Array<Bool> = [controls.NOTE_LEFT_P, controls.NOTE_DOWN_P, controls.NOTE_UP_P, controls.NOTE_RIGHT_P];

			if (controlArray.contains(true))
			{
				for (i in 0...controlArray.length)
				{
					if (controlArray[i]) {
						onKeyPress(new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true, -1, keysArray[i][0]));
					}
				}
			}
		}

		if (generatedMusic)
		{
			notes.forEachAlive(function(daNote:Note):Void
			{
				if (daNote.isSustainNote && holdingArray[daNote.noteData] && daNote.canBeHit && daNote.mustPress && !daNote.tooLate && !daNote.wasGoodHit) {
					goodNoteHit(daNote);
				}
			});
		}

		if (OptionData.controllerMode)
		{
			var controlArray:Array<Bool> = [controls.NOTE_LEFT_R, controls.NOTE_DOWN_R, controls.NOTE_UP_R, controls.NOTE_RIGHT_R];

			if (controlArray.contains(true))
			{
				for (i in 0...controlArray.length)
				{
					if (controlArray[i]) {
						onKeyRelease(new KeyboardEvent(KeyboardEvent.KEY_UP, true, true, -1, keysArray[i][0]));
					}
				}
			}
		}
	}

	private function endSong():Void
	{
		LoadingState.loadAndSwitchState(new editors.ChartingState());
	}

	function noteMissPress(direction:Int = 1):Void
	{
		FlxG.sound.play(Paths.getSoundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));

		combo = 0;
		songMisses++;

		vocals.volume = 0;
	}

	function noteMiss(daNote:Note):Void
	{
		notes.forEachAlive(function(note:Note):Void
		{
			if (daNote != note && daNote.mustPress && daNote.noteData == note.noteData && daNote.isSustainNote == note.isSustainNote && Math.abs(daNote.strumTime - note.strumTime) < 10)
			{
				note.kill();
				notes.remove(note, true);
				note.destroy();
			}
		});

		combo = 0;

		if (!daNote.ignoreNote)
		{
			songMisses++;
			vocals.volume = 0;
		}
	}

	function opponentNoteHit(daNote:Note):Void
	{
		if (PlayState.SONG.needsVoices) {
			vocals.volume = 1;
		}

		if (OptionData.opponentStrumsType == 'Glow' || (OptionData.opponentStrumsType == 'Glow no Sustains' && !daNote.isSustainNote))
		{
			var time:Float = 0.15;

			if (daNote.isSustainNote && !daNote.animation.curAnim.name.endsWith('end')) {
				time += 0.15;
			}
	
			StrumPlayAnim(true, Std.int(Math.abs(daNote.noteData)), time);
		}

		if (daNote.noteSplashHitByOpponent && !daNote.noteSplashDisabled && !daNote.isSustainNote) {
			spawnNoteSplashOnNote(daNote);
		}

		daNote.hitByOpponent = true;

		if (OptionData.sustainsType == 'Old' || !daNote.isSustainNote)
		{
			daNote.kill();
			notes.remove(daNote, true);
			daNote.destroy();
		}
	}

	function goodNoteHit(note:Note):Void
	{
		if (!note.wasGoodHit)
		{
			if (note.hitCausesMiss)
			{
				noteMiss(note);

				if (!note.noteSplashHitByOpponent && !note.noteSplashDisabled && !note.isSustainNote) {
					spawnNoteSplashOnNote(note);
				}

				note.wasGoodHit = true;

				if (!note.isSustainNote)
				{
					note.kill();
					notes.remove(note, true);
					note.destroy();
				}

				return;
			}
			else
			{
				if (note.quickNoteSplash) {
					spawnNoteSplashOnNote(note);
				}

				if (!note.ignoreNote)
				{
					popUpScore(note);

					if (!note.isSustainNote) {
						if (combo > 9999) combo = 9999;
					}
				}
			}

			playerStrums.forEach(function(spr:StrumNote):Void
			{
				if (Math.abs(note.noteData) == spr.ID) {
					spr.playAnim('confirm', true);
				}
			});

			note.wasGoodHit = true;
			vocals.volume = 1;

			if (OptionData.sustainsType == 'Old' || !note.isSustainNote)
			{
				note.kill();
				notes.remove(note, true);
				note.destroy();
			}
		}
	}

	function spawnNoteSplashOnNote(note:Note)
	{
		if (OptionData.splashOpacity > 0 && note != null)
		{
			var strum:StrumNote = null;

			if (!note.noteSplashHitByOpponent)
				strum = playerStrums.members[note.noteData];
			else
				strum = opponentStrums.members[note.noteData];

			if (strum != null) {
				spawnNoteSplash(strum.x, strum.y, note.noteData, note);
			}
		}
	}

	public function spawnNoteSplash(x:Float, y:Float, data:Int, ?note:Note = null):Void
	{
		var skin:String = 'noteSplashes';

		if (note.mustPress)
		{
			if (PlayState.SONG.splashSkin != null && PlayState.SONG.splashSkin.length > 0) {
				skin = PlayState.SONG.splashSkin;
			}
		}
		else
		{
			if (PlayState.SONG.splashSkin2 != null && PlayState.SONG.splashSkin2.length > 0) {
				skin = PlayState.SONG.splashSkin2;
			}
		}

		var hue:Float = OptionData.arrowHSV[data % 4][0] / 360;
		var sat:Float = OptionData.arrowHSV[data % 4][1] / 100;
		var brt:Float = OptionData.arrowHSV[data % 4][2] / 100;

		if (data > -1 && data < OptionData.arrowHSV.length)
		{
			hue = OptionData.arrowHSV[data][0] / 360;
			sat = OptionData.arrowHSV[data][1] / 100;
			brt = OptionData.arrowHSV[data][2] / 100;

			if (note != null)
			{
				skin = note.noteSplashTexture;

				hue = note.noteSplashHue;
				sat = note.noteSplashSat;
				brt = note.noteSplashBrt;
			}
		}

		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.setupNoteSplash(x, y, data, skin, note.mustPress, hue, sat, brt);
		grpNoteSplashes.add(splash);
	}

	function StrumPlayAnim(isDad:Bool, id:Int, time:Float):Void
	{
		var spr:StrumNote = null;

		if (isDad) {
			spr = opponentStrums.members[id];
		}
		else {
			spr = playerStrums.members[id];
		}

		if (spr != null)
		{
			spr.playAnim('confirm', true);
			spr.resetAnim = time;
		}
	}

	public override function stepHit():Void
	{
		super.stepHit();

		if (FlxG.sound.music.time > Conductor.songPosition + 20 || FlxG.sound.music.time < Conductor.songPosition - 20) {
			resyncVocals();
		}
	}

	public override function beatHit():Void
	{
		super.beatHit();

		if (generatedMusic) {
			notes.sort(FlxSort.byY, OptionData.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);
		}
	}

	function resyncVocals():Void
	{
		vocals.pause();

		FlxG.sound.music.play();

		Conductor.songPosition = FlxG.sound.music.time;

		vocals.time = Conductor.songPosition;
		vocals.play();
	}

	public override function destroy():Void
	{
		super.destroy();

		FlxG.sound.music.stop();

		vocals.stop();
		vocals.destroy();

		if (!OptionData.controllerMode)
		{
			FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
			FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
		}
	}
}