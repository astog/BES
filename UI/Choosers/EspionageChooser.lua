-- ===========================================================================
--
--	Slideout panel for selecting a new destination for a spy unit
--
-- ===========================================================================
include("InstanceManager");
include("AnimSidePanelSupport");
include("SupportFunctions");
include("PopupDialogSupport");
include("EspionageSupport");

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local RELOAD_CACHE_ID:string = "EspionageChooser"; -- Must be unique (usually the same as the file name)
local MAX_BEFORE_TRUNC_CHOOSE_NEXT:number = 210;

local EspionageChooserModes:table = {
	DESTINATION_CHOOSER	= 0;
	MISSION_CHOOSER		= 1;
};

local MISSION_CHOOSER_MISSIONSCROLLPANEL_RELATIVE_SIZE_Y = -126;
local DESTINATION_CHOOSER_MISSIONSCROLLPANEL_RELATIVE_SIZE_Y = -248;

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_AnimSupport			:table; -- AnimSidePanelSupport

-- Current EspionageChooserMode
local m_currentChooserMode	:number = -1;

-- Instance managers
local m_RouteChoiceIM		:table = InstanceManager:new("DestinationInstance", "DestinationButton",	Controls.DestinationStack);
local m_MissionStackIM		:table = InstanceManager:new("MissionInstance",		"MissionButton",		Controls.MissionStack);

-- Currently selected spy
local m_spy					:table = nil;

-- While in DESTINATION_CHOOSER - Currently selected destination
-- While in MISSION_CHOOSER - City where the selected spy resides
local m_city				:table = nil;

-- ===========================================================================
function Refresh()
	if m_spy == nil then
		UI.DataError("m_spy is nil. Expected to be currently selected spy.");
		Close();
		return;
	end

	if m_city == nil and m_currentChooserMode == EspionageChooserModes.MISSION_CHOOSER then
		UI.DataError("m_city is nil while updating espionage mission chooser. Expected to be city spy currently resides in.");
		Close();
		return;
	end


	RefreshTop();
	RefreshBottom();
end

-- ===========================================================================
function RefreshTop()
	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		-- DESTINATION_CHOOSER
		Controls.Title:SetText(Locale.ToUpper("LOC_ESPIONAGECHOOSER_PANEL_HEADER"));

		-- Controls that should never be visible in the DESTINATION_CHOOSER
		Controls.ActiveBoostContainer:SetHide(true);
		Controls.NoActiveBoostLabel:SetHide(true);

		-- If we've selected a city then show the district icons for that city
		if m_city then
			-- Update district info
			RefreshDistrictIcon(m_city, "DISTRICT_CITY_CENTER", Controls.CityCenterIcon);
			RefreshDistrictIcon(m_city, "DISTRICT_COMMERCIAL_HUB", Controls.CommericalIcon);
			RefreshDistrictIcon(m_city, "DISTRICT_THEATER", Controls.TheaterIcon);
			RefreshDistrictIcon(m_city, "DISTRICT_CAMPUS", Controls.ScienceIcon);
			RefreshDistrictIcon(m_city, "DISTRICT_INDUSTRIAL_ZONE", Controls.IndustrialIcon);
			RefreshDistrictIcon(m_city, "DISTRICT_NEIGHBORHOOD", Controls.NeighborhoodIcon);
			RefreshDistrictIcon(m_city, "DISTRICT_SPACEPORT", Controls.SpaceIcon);
			Controls.DistrictInfo:SetHide(false);

			Controls.SelectACityMessage:SetHide(true);

			UpdateCityBanner(m_city);
		else
			Controls.BannerBase:SetHide(true);
			Controls.DistrictInfo:SetHide(true);
			Controls.SelectACityMessage:SetHide(false);
		end
	else
		-- MISSION_CHOOSER
		Controls.Title:SetText(Locale.ToUpper("LOC_ESPIONAGECHOOSER_CHOOSE_MISSION"));

		-- Controls that should never be visible in the MISSION_CHOOSER
		Controls.SelectACityMessage:SetHide(true);
		Controls.DistrictInfo:SetHide(true);

		-- Controls that should always be visible in the MISSION_CHOOSER
		Controls.BannerBase:SetHide(false);

		UpdateCityBanner(m_city);

		-- Update active gain sources boost message
		local player = Players[Game.GetLocalPlayer()];
		local playerDiplomacy:table = player:GetDiplomacy();
		if playerDiplomacy then
			local boostedTurnsRemaining:number = playerDiplomacy:GetSourceTurnsRemaining(m_city);
			if boostedTurnsRemaining > 0 then
				TruncateStringWithTooltip(Controls.ActiveBoostLabel, MAX_BEFORE_TRUNC_CHOOSE_NEXT, Locale.Lookup("LOC_ESPIONAGECHOOSER_GAIN_SOURCES_ACTIVE", boostedTurnsRemaining));

				--Controls.ActiveBoostLabel:SetText(Locale.Lookup("LOC_ESPIONAGECHOOSER_GAIN_SOURCES_ACTIVE", boostedTurnsRemaining));
				Controls.ActiveBoostContainer:SetHide(false);
				Controls.NoActiveBoostLabel:SetHide(true);
			else
				Controls.ActiveBoostContainer:SetHide(true);
				Controls.NoActiveBoostLabel:SetHide(false);
			end
		end
	end
end

-- ===========================================================================
function RefreshBottom()
	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		-- DESTINATION_CHOOSER
		if m_city then
			Controls.DestinationPanel:SetHide(true);
			Controls.MissionPanel:SetHide(false);
			Controls.PossibleMissionsLabel:SetHide(false);
			Controls.DestinationChooserButtons:SetHide(false);
			Controls.MissionScrollPanel:SetParentRelativeSizeY(DESTINATION_CHOOSER_MISSIONSCROLLPANEL_RELATIVE_SIZE_Y);
			RefreshMissionList();
		else
			Controls.DestinationPanel:SetHide(false);
			Controls.MissionPanel:SetHide(true);
			RefreshDestinationList();
		end
	else
		-- MISSION_CHOOSER
		-- Controls that should never be visible in the MISSION_CHOOSER
		Controls.DestinationPanel:SetHide(true);
		Controls.PossibleMissionsLabel:SetHide(true);
		Controls.DestinationChooserButtons:SetHide(true);

		-- Controls that should always be visible in the MISSION_CHOOSER
		Controls.MissionPanel:SetHide(false);

		Controls.MissionScrollPanel:SetParentRelativeSizeY(MISSION_CHOOSER_MISSIONSCROLLPANEL_RELATIVE_SIZE_Y);
		RefreshMissionList();
	end
end

-- ===========================================================================
-- Refresh the destination list with all revealed non-city state owned cities
-- ===========================================================================
function RefreshDestinationList()
	m_RouteChoiceIM:ResetInstances();

	-- Add each players cities to destination list
	local players:table = Game.GetPlayers();
	for i, player in ipairs(players) do
		local playerInfluence:table = player:GetInfluence();
		-- Ignore city states (only they can receive influence)
		if playerInfluence and not playerInfluence:CanReceiveInfluence() then
			AddPlayerCities(player)
		end
	end

	Controls.DestinationPanel:CalculateInternalSize();
end

-- ===========================================================================
-- Refresh the mission list with counterspy targets for cities the player owns
-- and offensive spy operations for cities owned by other players
-- ===========================================================================
function RefreshMissionList()
	m_MissionStackIM:ResetInstances();

	-- Determine if this is a owned by the local player
	if m_city:GetOwner() == Game.GetLocalPlayer() then
		-- If we own this city show a list of possible counterspy targets
		for operation in GameInfo.UnitOperations() do
			if operation.OperationType == "UNITOPERATION_SPY_COUNTERSPY" then
				local cityPlot:table = Map.GetPlot(m_city:GetX(), m_city:GetY());
				local canStart:boolean, results:table = UnitManager.CanStartOperation( m_spy, operation.Hash, cityPlot, false, true);
				if canStart then
					-- Check the CanStartOperation results for a target district plot
					for i,districtPlotID in ipairs(results[UnitOperationResults.PLOTS]) do
						AddCounterspyOperation(operation, districtPlotID);
					end
				end
			end
		end
	else
		-- Fill mission stack with possible missions at selected city
		for operation in GameInfo.UnitOperations() do
			if operation.CategoryInUI == "OFFENSIVESPY" then
				local cityPlot:table = Map.GetPlot(m_city:GetX(), m_city:GetY());
				local canStart:boolean, results:table = UnitManager.CanStartOperation( m_spy, operation.Hash, cityPlot, false, true);
				if canStart then
					AddAvailableOffensiveOperation(operation, results, cityPlot);
				else
					---- If we're provided with a failure reason then show the mission disabled
					if results and results[UnitOperationResults.FAILURE_REASONS] then
						AddDisabledOffensiveOperation(operation, results, cityPlot);
					end
				end
			end
		end
	end

	Controls.MissionScrollPanel:CalculateInternalSize();
	Controls.MissionPanel:ReprocessAnchoring();
end

-- ===========================================================================
function AddCounterspyOperation(operation:table, districtPlotID:number)
	local missionInstance:table = m_MissionStackIM:GetInstance();

	-- Find district
	local cityDistricts:table = m_city:GetDistricts();
	for i,district in cityDistricts:Members() do
		local districtPlot:table = Map.GetPlot(district:GetX(), district:GetY());
		if districtPlot:GetIndex() == districtPlotID then
			local districtInfo:table = GameInfo.Districts[district:GetType()];

			-- Update mission info
			missionInstance.MissionName:SetText(Locale.Lookup(operation.Description));
			missionInstance.MissionDetails:SetText(Locale.Lookup("LOC_ESPIONAGECHOOSER_COUNTERSPY", Locale.Lookup(districtInfo.Name)));
			missionInstance.MissionDetails:SetColorByName("White");

			-- Update mission icon
			local iconString:string = "ICON_" .. districtInfo.DistrictType;
			local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(iconString,32);
			if textureSheet then
				missionInstance.MissionIcon:Resize(32,32);
				missionInstance.MissionIcon:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
			else
				UI.DataError("Failed to find icon for district(" .. districtInfo.DistrictType .. ")");
			end

			-- If this is the mission choose set callback to open up mission briefing
			if m_currentChooserMode == EspionageChooserModes.MISSION_CHOOSER then
				missionInstance.MissionButton:RegisterCallback( Mouse.eLClick, function() OnCounterspySelected(districtPlot); end );
			end
		end
	end

	missionInstance.MissionStatsStack:SetHide(true);

	-- While in DESTINATION_CHOOSER mode we don't want the buttons to act
	-- like buttons since they cannot be clicked in that mode
	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		missionInstance.MissionButton:SetDisabled(true);
		missionInstance.MissionButton:SetVisState(0);
	else
		missionInstance.MissionButton:SetDisabled(false);
	end

	-- Default the selector brace to hidden
	missionInstance.SelectorBrace:SetColor(0x00FFFFFF);
end

-- ===========================================================================
function AddOffensiveOperation(operation:table, result:table, targetCityPlot:table)
	local missionInstance:table = m_MissionStackIM:GetInstance();
	missionInstance.MissionButton:SetDisabled(false);

	-- Update mission name
	missionInstance.MissionName:SetText(Locale.Lookup(operation.Description));

	-- Update mission icon
	local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(operation.Icon,40);
	missionInstance.MissionIcon:Resize(40,40);
	missionInstance.MissionIcon:SetTexture(textureOffsetX, textureOffsetY, textureSheet);

	-- Update turns to completed
	local eOperation:number = GameInfo.UnitOperations[operation.Hash].Index;
	local turnsToComplete:number = UnitManager.GetTimeToComplete(eOperation, m_spy);
	missionInstance.TurnsToCompleteLabel:SetText(turnsToComplete);

	-- Update mission success chance
	local resultProbability:table = UnitManager.GetResultProbability(eOperation, m_spy, targetCityPlot);
	if resultProbability["ESPIONAGE_SUCCESS_UNDETECTED"] then
		local probability:number = resultProbability["ESPIONAGE_SUCCESS_UNDETECTED"];

		-- Add ESPIONAGE_SUCCESS_MUST_ESCAPE
		if resultProbability["ESPIONAGE_SUCCESS_MUST_ESCAPE"] then
			probability = probability + resultProbability["ESPIONAGE_SUCCESS_MUST_ESCAPE"];
		end

		probability = math.floor((probability * 100)+0.5);
		missionInstance.ProbabilityLabel:SetText(probability .. "%");

		-- Set Color
		if probability > 85 then
			missionInstance.ProbabilityLabel:SetColorByName("OperationChance_Green");
		elseif probability > 65 then
			missionInstance.ProbabilityLabel:SetColorByName("OperationChance_YellowGreen");
		elseif probability > 45 then
			missionInstance.ProbabilityLabel:SetColorByName("OperationChance_Yellow");
		elseif probability > 25 then
			missionInstance.ProbabilityLabel:SetColorByName("OperationChance_Orange");
		else
			missionInstance.ProbabilityLabel:SetColorByName("OperationChance_Red");
		end
	end

	-- result is the data bundle retruned by CanStartOperation container useful information about the operation query
	-- If the results contain a plot ID then show that as the target district
	if result and result[UnitOperationResults.PLOTS] then
		for i,districtPlotID in ipairs(result[UnitOperationResults.PLOTS]) do
			local districts:table = m_city:GetDistricts();
			for i,district in districts:Members() do
				local districtPlot:table = Map.GetPlot(district:GetX(), district:GetY());
				if districtPlot:GetIndex() == districtPlotID then
					local districtInfo:table = GameInfo.Districts[district:GetType()];
					missionInstance.MissionDistrictName:SetText(Locale.Lookup(districtInfo.Name));
					local iconString:string = "[Icon_" .. districtInfo.DistrictType .. "]";
					missionInstance.MissionDistrictIcon:SetText(iconString);
				end
			end
		end
	else -- Default to show city center
		missionInstance.MissionDistrictName:SetText(Locale.Lookup("LOC_DISTRICT_CITY_CENTER_NAME"));
		missionInstance.MissionDistrictIcon:SetText("[Icon_DISTRICT_CITYCENTER]");
	end

	missionInstance.MissionStatsStack:SetHide(false);
	missionInstance.MissionStatsStack:CalculateSize();
	missionInstance.MissionStatsStack:ReprocessAnchoring();

	-- Default the selector brace to hidden
	missionInstance.SelectorBrace:SetColor(0x00FFFFFF);

	return missionInstance;
end

-- ===========================================================================
function AddDisabledOffensiveOperation(operation:table, result:table, targetCityPlot:table)
	local missionInstance:table = AddOffensiveOperation(operation, result, targetCityPlot);

	-- Update mission description with reason the mission is disabled
	if result and result[UnitOperationResults.FAILURE_REASONS] then
		local failureReasons:table = result[UnitOperationResults.FAILURE_REASONS];
		local missionDetails:string = "";

		-- Add all given reasons into mission details
		for i,reason in ipairs(failureReasons) do
			if missionDetails == "" then
				missionDetails = reason;
			else
				missionDetails = missionDetails .. "[NEWLINE]" .. reason;
			end
		end

		missionInstance.MissionDetails:SetText(missionDetails);
		missionInstance.MissionDetails:SetColorByName("Red");
	end

	missionInstance.MissionStack:CalculateSize();
	missionInstance.MissionButton:DoAutoSize();

	-- Disable mission button
	missionInstance.MissionButton:SetDisabled(true);
end

-- ===========================================================================
function AddAvailableOffensiveOperation(operation:table, result:table, targetCityPlot:table)
	local missionInstance:table = AddOffensiveOperation(operation, result, targetCityPlot);

	-- Update mission details
	missionInstance.MissionDetails:SetText(GetFormattedOperationDetailText(operation, m_spy, m_city));
	missionInstance.MissionDetails:SetColorByName("White");

	missionInstance.MissionStack:CalculateSize();
	missionInstance.MissionButton:DoAutoSize();

	-- If this is the mission choose set callback to open up mission briefing
	if m_currentChooserMode == EspionageChooserModes.MISSION_CHOOSER then
		missionInstance.MissionButton:RegisterCallback( Mouse.eLClick, function() OnMissionSelected(operation, missionInstance); end );
	end

	-- While in DESTINATION_CHOOSER mode we don't want the buttons to act
	-- like buttons since they cannot be clicked in that mode
	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		missionInstance.MissionButton:SetDisabled(true);
		missionInstance.MissionButton:SetVisState(0);
	else
		missionInstance.MissionButton:SetDisabled(false);
	end
end

-- ===========================================================================
function OnCounterspySelected(districtPlot:table)
	local tParameters:table = {};
	tParameters[UnitOperationTypes.PARAM_X] = districtPlot:GetX();
	tParameters[UnitOperationTypes.PARAM_Y] = districtPlot:GetY();

	UnitManager.RequestOperation(m_spy, UnitOperationTypes.SPY_COUNTERSPY, tParameters);
end

-- ===========================================================================
function OnMissionSelected(operation:table, instance:table)
	LuaEvents.EspionageChooser_ShowMissionBriefing(operation.Hash, m_spy:GetID());

	-- Hide all selection borders before selecting another
	for i=1, m_MissionStackIM.m_iCount, 1 do
		local otherInstances:table = m_MissionStackIM:GetAllocatedInstance(i);
		if otherInstances then
			otherInstances.SelectorBrace:SetColor(0x00000000);
		end
	end

	-- Show selected border over instance
	instance.SelectorBrace:SetColor(0xFFFFFFFF);
end

-- ===========================================================================
function UpdateCityBanner(city:table)
	local backColor:number, frontColor:number  = UI.GetPlayerColors( city:GetOwner() );
	local darkerBackColor:number = DarkenLightenColor(backColor,(-85),238);
	local brighterBackColor:number = DarkenLightenColor(backColor,90,255);

	Controls.BannerBase:SetColor( backColor );
	Controls.BannerDarker:SetColor( darkerBackColor );
	Controls.BannerLighter:SetColor( brighterBackColor );
	Controls.CityName:SetColor( frontColor );
	Controls.CityName:SetText(Locale.ToUpper(city:GetName()));
	Controls.BannerBase:SetHide(false);

	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		-- Update travel time
		local travelTime:number = UnitManager.GetTravelTime(m_spy, m_city);
		local establishTime:number = UnitManager.GetEstablishInCityTime(m_spy, m_city);
		local totalTravelTime:number = travelTime + establishTime;
		Controls.TravelTime:SetColor( frontColor );
		Controls.TravelTime:SetText(tostring(totalTravelTime));
		Controls.TravelTimeIcon:SetColor( frontColor )
		Controls.TravelTimeStack:ReprocessAnchoring();
		Controls.TravelTimeStack:SetHide(false);

		-- Update travel time tool tip string
		Controls.BannerBase:SetToolTipString(Locale.Lookup("LOC_ESPIONAGECHOOSER_TRAVEL_TIME_TOOLTIP", travelTime, establishTime));
	else
		Controls.TravelTimeStack:SetHide(true);
		Controls.BannerBase:SetToolTipString("");
	end
end

-- ===========================================================================
function AddPlayerCities(player:table)
	local playerCities:table = player:GetCities();
	for j, city in playerCities:Members() do
		-- Check if the city is revealed
		local localPlayerVis:table = PlayersVisibility[Game.GetLocalPlayer()];
		if localPlayerVis:IsRevealed(city:GetX(), city:GetY()) then
			AddDestination(city);
		end
	end
end

-- ===========================================================================
function AddDestination(city:table)
	local destinationInstance:table = m_RouteChoiceIM:GetInstance();

	-- Update city name and banner color
	destinationInstance.CityName:SetText(Locale.ToUpper(city:GetName()));

	local backColor:number, frontColor:number  = UI.GetPlayerColors( city:GetOwner() );
	local darkerBackColor:number = DarkenLightenColor(backColor,(-85),238);
	local brighterBackColor:number = DarkenLightenColor(backColor,90,255);

	destinationInstance.BannerBase:SetColor( backColor );
	destinationInstance.BannerDarker:SetColor( darkerBackColor );
	destinationInstance.BannerLighter:SetColor( brighterBackColor );
	destinationInstance.CityName:SetColor( frontColor );

	-- Update travel time
	local travelTime:number = UnitManager.GetTravelTime(m_spy, city);
	local establishTime:number = UnitManager.GetEstablishInCityTime(m_spy, city);
	local totalTravelTime:number = travelTime + establishTime;
	destinationInstance.TravelTime:SetColor( frontColor );
	destinationInstance.TravelTime:SetText(tostring(totalTravelTime));
	destinationInstance.TravelTimeIcon:SetColor( frontColor )
	destinationInstance.TravelTimeStack:ReprocessAnchoring();

	-- Update travel time tool tip string
	destinationInstance.BannerBase:SetToolTipString(Locale.Lookup("LOC_ESPIONAGECHOOSER_TRAVEL_TIME_TOOLTIP", travelTime, establishTime));

	-- Update district icons
	RefreshDistrictIcon(city, "DISTRICT_CITY_CENTER", destinationInstance.CityCenterIcon);
	RefreshDistrictIcon(city, "DISTRICT_COMMERCIAL_HUB", destinationInstance.CommericalIcon);
	RefreshDistrictIcon(city, "DISTRICT_THEATER", destinationInstance.TheaterIcon);
	RefreshDistrictIcon(city, "DISTRICT_CAMPUS", destinationInstance.ScienceIcon);
	RefreshDistrictIcon(city, "DISTRICT_INDUSTRIAL_ZONE", destinationInstance.IndustrialIcon);
	RefreshDistrictIcon(city, "DISTRICT_NEIGHBORHOOD", destinationInstance.NeighborhoodIcon);
	RefreshDistrictIcon(city, "DISTRICT_SPACEPORT", destinationInstance.SpaceIcon);

	-- Set button callback
	destinationInstance.DestinationButton:RegisterCallback( Mouse.eLClick, function() OnSelectDestination(city);  end);
end

-- ===========================================================================
function RefreshDistrictIcon(city:table, districtType:string, districtIcon:table)
	local hasDistrict:boolean = false;
	local cityDistricts:table = city:GetDistricts();
	for i, district in cityDistricts:Members() do
		if district:IsComplete() then
			local districtInfo:table = GameInfo.Districts[district:GetType()];
			if districtInfo.DistrictType == districtType then
				hasDistrict = true;
			end
		end
	end

	if hasDistrict then
		districtIcon:SetHide(false);
	else
		districtIcon:SetHide(true);
	end
end

-- ===========================================================================
function OnSelectDestination(city:table)
	m_city = city;

	-- Look at the selected destination
	UI.LookAtPlot(m_city:GetX(), m_city:GetY());

	Refresh();
end

-- ===========================================================================
function TeleportToSelectedCity()
	if not m_city or not m_spy then
		return
	end

	local tParameters:table = {};
	tParameters[UnitOperationTypes.PARAM_X] = m_city:GetX();
	tParameters[UnitOperationTypes.PARAM_Y] = m_city:GetY();

	if (UnitManager.CanStartOperation( m_spy, UnitOperationTypes.SPY_TRAVEL_NEW_CITY, Map.GetPlot(m_city:GetX(), m_city:GetY()), tParameters)) then
		UnitManager.RequestOperation( m_spy, UnitOperationTypes.SPY_TRAVEL_NEW_CITY, tParameters);
		UI.SetInterfaceMode(InterfaceModeTypes.SELECTION);
	end
end

-- ===========================================================================
function Open()
	-- Set chooser mode based on interface mode
	if UI.GetInterfaceMode() == InterfaceModeTypes.SPY_TRAVEL_TO_CITY then
		m_currentChooserMode = EspionageChooserModes.DESTINATION_CHOOSER;
	else
		m_currentChooserMode = EspionageChooserModes.MISSION_CHOOSER;
	end

	-- Cache the selected spy
	local selectedUnit:table = UI.GetHeadSelectedUnit();
	if selectedUnit then
		local selectedUnitInfo:table = GameInfo.Units[selectedUnit:GetUnitType()];
		if selectedUnitInfo and selectedUnitInfo.Spy then
			m_spy = selectedUnit;
		else
			m_spy = nil;
			return;
		end
	else
		m_spy = nil;
		return;
	end

	-- Set m_city depending on the mode
	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		-- Clear m_city for Destination Chooser as it will be the city the player chooses
		m_city = nil;
	else
		-- Set m_city to city where in for Mission Chooser as we only want missions from this city
		local spyPlot:table = Map.GetPlot(m_spy:GetX(), m_spy:GetY());
		local city:table = Cities.GetPlotPurchaseCity(spyPlot);
		m_city = city;
	end

	if not m_AnimSupport:IsVisible() then
		m_AnimSupport:Show();
	end

	Refresh();

	-- Play opening sound
	UI.PlaySound("Tech_Tray_Slide_Open");
end

-- ===========================================================================
function Close()
	if m_AnimSupport:IsVisible() then
		m_AnimSupport:Hide();
		UI.SetInterfaceMode(InterfaceModeTypes.SELECTION);
        UI.PlaySound("Tech_Tray_Slide_Closed");
	end
end

-- ===========================================================================
function OnConfirmPlacement()
	-- If we're selecting a city we own and we're already there switch to the counterspy mission chooser
	local spyPlot:table = Map.GetPlot(m_spy:GetX(), m_spy:GetY());
	local spyCity:table = Cities.GetPlotPurchaseCity(spyPlot);
	if m_city:GetOwner() == Game.GetLocalPlayer() and spyCity:GetID() == m_city:GetID() and m_city:GetOwner() == spyCity:GetOwner() then
		m_currentChooserMode = EspionageChooserModes.MISSION_CHOOSER;
		Refresh();
	else
		TeleportToSelectedCity();
		UI.PlaySound("UI_Spy_Confirm_Placement");
	end
end

-- ===========================================================================
function OnCancel()
	m_city = nil;
	Refresh();
end

-- ===========================================================================
function OnInterfaceModeChanged( oldMode:number, newMode:number )
	if oldMode == InterfaceModeTypes.SPY_CHOOSE_MISSION and newMode ~= InterfaceModeTypes.SPY_TRAVEL_TO_CITY then
		if m_AnimSupport:IsVisible() then
			Close();
		end
	end
	if oldMode == InterfaceModeTypes.SPY_TRAVEL_TO_CITY and newMode ~= InterfaceModeTypes.SPY_CHOOSE_MISSION then
		if m_AnimSupport:IsVisible() then
			Close();
		end
	end

	if newMode == InterfaceModeTypes.SPY_TRAVEL_TO_CITY then
		Open();
	end
	if newMode == InterfaceModeTypes.SPY_CHOOSE_MISSION then
		Open();
	end
end

-- ===========================================================================
function OnUnitSelectionChanged( playerID : number, unitID : number, hexI : number, hexJ : number, hexK : number, bSelected : boolean, bEditable : boolean)
	-- Make sure we're the local player and not observing
	if playerID ~= Game.GetLocalPlayer() or playerID == -1 then
		return;
	end

	-- Make sure the selected unit is a spy and that we don't have a current spy operation
	GoToProperInterfaceMode(UI.GetHeadSelectedUnit());
end

------------------------------------------------------------------
function OnUnitActivityChanged( playerID :number, unitID :number, eActivityType :number)
	-- Make sure we're the local player and not observing
	if playerID ~= Game.GetLocalPlayer() or playerID == -1 then
		return;
	end

	GoToProperInterfaceMode(UI.GetHeadSelectedUnit());
end

-- ===========================================================================
function GoToProperInterfaceMode(spyUnit:table)
	local desiredInterfaceMode:number = nil;

	if spyUnit and spyUnit:IsReadyToMove() then
		local spyUnitInfo:table = GameInfo.Units[spyUnit:GetUnitType()];
		if spyUnitInfo.Spy then
			-- Make sure the spy is awake
			local activityType:number = UnitManager.GetActivityType(spyUnit);
			if activityType == ActivityTypes.ACTIVITY_AWAKE then
				local spyPlot:table = Map.GetPlot(spyUnit:GetX(), spyUnit:GetY());
				local city:table = Cities.GetPlotPurchaseCity(spyPlot);
				if city and city:GetOwner() == Game.GetLocalPlayer() then
					--UI.SetInterfaceMode(InterfaceModeTypes.SPY_TRAVEL_TO_CITY);
					desiredInterfaceMode = InterfaceModeTypes.SPY_TRAVEL_TO_CITY;
				else
					--UI.SetInterfaceMode(InterfaceModeTypes.SPY_CHOOSE_MISSION);
					desiredInterfaceMode = InterfaceModeTypes.SPY_CHOOSE_MISSION;
				end
			end
		end
	end

	if desiredInterfaceMode then
		if UI.GetInterfaceMode() == desiredInterfaceMode then
			-- If already in the right interfacec mode then just refresh
			Open();
		else
			UI.SetInterfaceMode(desiredInterfaceMode);
		end
	else
		-- If not going to an espionage interface mode then close if we're open
		if m_AnimSupport:IsVisible() then
			Close();
		end
	end
end

------------------------------------------------------------------------------------------------
function OnLocalPlayerTurnEnd()
	if(GameConfiguration.IsHotseat()) then
		Close();
	end
end

-- ===========================================================================
function OnMissionBriefingClosed()
	if m_AnimSupport:IsVisible() then
		-- If we're shown and we close a mission briefing hide the selector brace for all to make sure it gets hidden probably
		for i=1,m_MissionStackIM.m_iCount,1 do
			local instance:table = m_MissionStackIM:GetAllocatedInstance(i);
			if instance then
				instance.SelectorBrace:SetColor(0x00FFFFFF);
			end
		end
	end
end

-- ===========================================================================
--	LUA Event
--	Explicit close (from partial screen hooks), part of closing everything,
-- ===========================================================================
function OnCloseAllExcept( contextToStayOpen:string )
	if contextToStayOpen == ContextPtr:GetID() then return; end
	Close();
end

-- ===========================================================================
function OnClose()
	Close();
end

-- ===========================================================================
--	UI EVENT
-- ===========================================================================
function OnInit(isReload:boolean)
	if isReload then
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);
	end
end

-- ===========================================================================
--	UI EVENT
-- ===========================================================================
function OnShutdown()
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isVisible", m_AnimSupport:IsVisible());
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "selectedCity", m_city);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "selectedSpy", m_spy);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "currentChooserMode", m_currentChooserMode);
end

-- ===========================================================================
--	LUA EVENT
--	Reload support
-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)
	if context == RELOAD_CACHE_ID then
		if contextTable["currentChooserMode"] ~= nil then
			m_currentChooserMode = contextTable["currentChooserMode"];
		end
		if contextTable["selectedCity"] ~= nil then
			m_city = contextTable["selectedCity"];
		end
		if contextTable["selectedSpy"] ~= nil then
			m_spy = contextTable["selectedSpy"];
		end
		if contextTable["isVisible"] ~= nil and contextTable["isVisible"] then
			m_AnimSupport:Show();
			Refresh();
		end
	end
end

-- ===========================================================================
--	INIT
-- ===========================================================================
function Initialize()
	-- Lua Events
	LuaEvents.EspionagePopup_MissionBriefingClosed.Add( OnMissionBriefingClosed );

	-- Control Events
	Controls.ConfirmButton:RegisterCallback( Mouse.eLClick, OnConfirmPlacement );
	Controls.ConfirmButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.CancelButton:RegisterCallback( Mouse.eLClick, OnCancel );
	Controls.CancelButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnClose );
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	-- Game Engine Events
	Events.InterfaceModeChanged.Add( OnInterfaceModeChanged );
	Events.UnitSelectionChanged.Add( OnUnitSelectionChanged );
	Events.UnitActivityChanged.Add( OnUnitActivityChanged );
	Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );

	-- Animation controller
	m_AnimSupport = CreateScreenAnimation(Controls.SlideAnim);

	-- Animation controller events
	Events.SystemUpdateUI.Add(m_AnimSupport.OnUpdateUI);
	ContextPtr:SetInputHandler(m_AnimSupport.OnInputHandler, true);

	-- Hot-Reload Events
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShutdown(OnShutdown);
	LuaEvents.GameDebug_Return.Add(OnGameDebugReturn);
end
Initialize();
