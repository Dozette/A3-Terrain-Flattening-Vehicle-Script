/*
    Advanced Terrain Flattener Script for Arma 3
    Author: Dozette
    Description: Creates smooth terrain flattening around a moving vehicle
*/

// Configuration
private _radius = 20;
private _smoothingRadius = 20;
private _gridSize = 3; // Reduced grid size for better smoothing
private _maxElevationChange = 0.1;
private _updateInterval = 0.5;
private _maxPointsPerUpdate = 2000; // Increased points per update
private _minDistanceToUpdate = 1;

// Function to handle map objects
fn_handleMapObjects = {
    params ["_vehicle", "_radius", "_hide"];
    
    private _pos = getPos _vehicle;
    
    // Get all terrain objects in the radius
    private _terrainObjects = nearestTerrainObjects [_pos, [], _radius];
    
    {
        if (!(_x isKindOf "Man") && !(_x isKindOf "AllVehicles") && !(_x isKindOf "Air") && !(_x isKindOf "Ship")) then {
            if (_hide) then {
                // Make object completely transparent
                _x setObjectTextureGlobal [0, "#(argb,8,8,3)color(0,0,0,0)"];
                _x hideObjectGlobal true;
                _x enableSimulationGlobal false;
                // Move far below ground and offset from original position
                private _originalPos = getPosASL _x;
                _x setPosASL [_originalPos select 0, _originalPos select 1, -5000];
                _x setVectorUp [0,0,-1];  // Flip object upside down
                _x setVelocity [0,0,0];
            };
        };
    } forEach _terrainObjects;
};

// Function to flatten terrain
fn_flattenTerrain = {
    params ["_vehicle", "_radius", "_smoothingRadius", "_gridSize", "_maxElevationChange", "_maxPointsPerUpdate"];
    
    // Only run on the server
    if (!isServer) exitWith {};
    
    private _modelPos = getPos _vehicle;
    private _targetHeight = _vehicle getVariable ["terrainFlatteningHeight", 0];
    private _objectBaseHeight = _modelPos select 2;
    
    private _setHeightArray = [];
    private _count = 0;
    
    // Main flattening area (optimized)
    for "_dx" from -_radius to _radius step _gridSize do {
        for "_dy" from -_radius to _radius step _gridSize do {
            if (_count >= _maxPointsPerUpdate) exitWith {};
            
            if ((_dx * _dx + _dy * _dy) <= (_radius * _radius)) then {
                private _xPos = (_modelPos select 0) + _dx;
                private _yPos = (_modelPos select 1) + _dy;
                
                private _adjustedHeight = _targetHeight;
                _setHeightArray pushBack [_xPos, _yPos, _adjustedHeight];
                _count = _count + 1;
                
                if (_count >= _maxPointsPerUpdate) exitWith {};
            };
        };
        if (_count >= _maxPointsPerUpdate) exitWith {};
    };
    
    // Apply height changes if we have points
    if (count _setHeightArray > 0) then {
        setTerrainHeight [_setHeightArray, true];
    };
    
    // Only process smoothing if we haven't hit the point limit
    if (_count < _maxPointsPerUpdate) then {
        _setHeightArray = [];
        _count = 0;
        
        // Smoothing area (optimized)
        for "_dx" from -_smoothingRadius to _smoothingRadius step _gridSize do {
            for "_dy" from -_smoothingRadius to _smoothingRadius step _gridSize do {
                if (_count >= _maxPointsPerUpdate) exitWith {};
                
                private _distance = sqrt ((_dx * _dx) + (_dy * _dy));
                if (_distance > _radius && _distance <= _smoothingRadius) then {
                    private _xPos = (_modelPos select 0) + _dx;
                    private _yPos = (_modelPos select 1) + _dy;
                    private _currentHeight = getTerrainHeightASL [_xPos, _yPos];
                    
                    private _smoothingFactor = (_distance - _radius) / (_smoothingRadius - _radius);
                    private _adjustedHeight = _currentHeight + (_targetHeight - _currentHeight) * (1 - _smoothingFactor);
                    _setHeightArray pushBack [_xPos, _yPos, _adjustedHeight];
                    _count = _count + 1;
                    
                    if (_count >= _maxPointsPerUpdate) exitWith {};
                };
            };
            if (_count >= _maxPointsPerUpdate) exitWith {};
        };
        
        // Apply any remaining height changes
        if (count _setHeightArray > 0) then {
            setTerrainHeight [_setHeightArray, true];
        };
    };
};

// Main loop
params ["_vehicle"];
[_vehicle, _radius, _smoothingRadius, _gridSize, _maxElevationChange, _updateInterval, _minDistanceToUpdate, _maxPointsPerUpdate] spawn {
    params ["_vehicle", "_radius", "_smoothingRadius", "_gridSize", "_maxElevationChange", "_updateInterval", "_minDistanceToUpdate", "_maxPointsPerUpdate"];
    
    // Initialize flattening height
    _vehicle setVariable ["terrainFlatteningHeight", 0, true];
    
    // Add toggle action to vehicle
    private _actionId = _vehicle addAction [
        "<t color='#00FF00'>Toggle Terrain Flattening</t>",
        {
            params ["_target", "_caller", "_actionId", "_arguments"];
            _arguments params ["_radius", "_smoothingRadius", "_gridSize", "_maxElevationChange", "_maxPointsPerUpdate"];
            [_target, _actionId, _radius, _smoothingRadius, _gridSize, _maxElevationChange, _maxPointsPerUpdate] call fn_toggleTerrainFlattening;
        },
        [_radius, _smoothingRadius, _gridSize, _maxElevationChange, _maxPointsPerUpdate],
        1.5,
        true,
        true,
        "",
        "driver _target == _this"
    ];
    
    // Add scroll wheel menu for setting height
    _vehicle addAction [
        "<t color='#00FF00'>Set Flattening Height to Current Altitude</t>",
        {
            params ["_target", "_caller"];
            private _currentHeight = getTerrainHeightASL (getPosASL _target);
            _target setVariable ["terrainFlatteningHeight", _currentHeight, true];
            hint format ["Flattening height set to: %1m", round _currentHeight];
        },
        nil,
        1.5,
        true,
        true,
        "",
        "driver _target == _this"
    ];
    
    private _lastPos = getPos _vehicle;
    
    while {alive _vehicle} do {
        private _currentPos = getPos _vehicle;
        private _distance = _currentPos distance2D _lastPos;
        
        // Only update if vehicle has moved enough and flattening is active
        if (_distance >= _minDistanceToUpdate && {_vehicle getVariable ["terrainFlatteningActive", false]}) then {
            // Only run terrain flattening on the server
            if (isServer) then {
                [_vehicle, _radius, _smoothingRadius, _gridSize, _maxElevationChange, _maxPointsPerUpdate] spawn {
                    params ["_vehicle", "_radius", "_smoothingRadius", "_gridSize", "_maxElevationChange", "_maxPointsPerUpdate"];
                    [_vehicle, _radius, _smoothingRadius, _gridSize, _maxElevationChange, _maxPointsPerUpdate] call fn_flattenTerrain;
                };
            };
            // Hide objects as vehicle moves (runs on all clients)
            [_vehicle, _radius, true] call fn_handleMapObjects;
            _lastPos = _currentPos;
        };
        
        sleep _updateInterval;
    };
    
    // Remove action when vehicle is destroyed
    _vehicle removeAction _actionId;
};

// Function to toggle terrain flattening
fn_toggleTerrainFlattening = {
    params ["_vehicle", "_handle", "_radius", "_smoothingRadius", "_gridSize", "_maxElevationChange", "_maxPointsPerUpdate"];
    
    if (isNil {_vehicle getVariable "terrainFlatteningActive"}) then {
        _vehicle setVariable ["terrainFlatteningActive", false, true];
    };
    
    private _isActive = _vehicle getVariable "terrainFlatteningActive";
    _vehicle setVariable ["terrainFlatteningActive", !_isActive, true];
    
    // Control the CRV-6e Bobcat's plough
    if (_vehicle isKindOf "B_APC_Tracked_01_CRV_F") then {
        if (!_isActive) then {
            _vehicle animate ["moveplow", 1]; // Lower the plough
            [_vehicle, _radius, true] call fn_handleMapObjects; // Hide objects
            hint format ["Terrain Flattening: ON\nPlough: Lowered\nObjects: Hidden\nTarget Height: %1m", round (_vehicle getVariable ["terrainFlatteningHeight", 0])];
        } else {
            _vehicle animate ["moveplow", 0]; // Raise the plough
            hint "Terrain Flattening: OFF\nPlough: Raised";
        };
    } else {
        if (!_isActive) then {
            [_vehicle, _radius, true] call fn_handleMapObjects; // Hide objects
            hint format ["Terrain Flattening: ON\nObjects: Hidden\nTarget Height: %1m", round (_vehicle getVariable ["terrainFlatteningHeight", 0])];
        } else {
            hint "Terrain Flattening: OFF";
        };
    };
};