classdef Initializer < handle
% Base class for data initialization objects.
	
		
%===================================================================================================
	properties (Constant = true, Transient = true) %							C O N S T A N T	 [P]
    end%CONSTANT
	
%===================================================================================================
    properties (SetAccess = public, GetAccess = public) %							P U B L I C  [P]
        activeSlices;   % Which slices to save.                             struct
        bcInfinity      % Number of cells beyond grid to use as infinity.   int
        bcMode;         % Boundary value types and settings.                struct
        cfl;            % Multiplicative coefficient for timesteps.         double
        customSave;     % Which arrays to save in custom save slices.       struct
        debug;          % Run Imogen in debug mode.                         logical *
        dGrid;          % Grid cell spacing and parameters.                 struct
        gamma;          % Polytropic equation of state constant.            double
        gravity;        % Gravity sub-initializer object containing all     GravitySubInitializer
                        %   gravity related settings.
        grid;           % # of cells for each spatial dimension (1x3).      double
        info;           % Short information describing run.                 string
        image;          % Which images to save.                             struct
        iterMax;        % Maximum iterations for the run.                   int
        wallMax;        % Maximum wall time allowed for the run in hours.   double
        minMass;        % Minimum allowed mass density value.               double
        mode;           % Specifies the portions of the code are active.    struct
        notes;          % Lengthy information regarding a run.              string
        ppSave;         % Percentage of execution between slice saves.      struct
        profile;        % Specifies enabling of performance profiling.      logical
        runCode;        % Code used to specify experiment type.             string
        alias;          % Unique identifier for the run.                    string
        save;           % Enable/disable saving data to files for a run.    logical
        slice;          % Indices for slices when saving data (1x3).        int
        specSaves;      % Arrays of special iterations used to save data.   struct
        thresholdMass;  % Minium mass acted on by gravitational forces      double
        timeMax;        % Maximum simulation time before run exits.         double
        timeUpdateMode; % Enumerated frequency of timestep updates.         int
        treadmill;      % Treadmilling direction, inactive if empty.        string
        viscosity;      % Viscosity sub initializer object.                 ViscositySubInitializer
        radiation;      % Radiation sub initializer objet.                  RadiationSubInitializer
        logProperties;  % List of class properties to include in run.log    cell
        fluxLimiter;    % Specifies the flux limiter(s) to use.             struct

        useGPU;         % if true, Imogen tries to run on a GPU             logical
        gpuDeviceNumber;      % ID of the device to attempt to run on
    end %PUBLIC

%===================================================================================================
    properties (Dependent = true) %											   D E P E N D E N T [P]
        fades;
        saveSlicesSpecified; % Specifies if save slices have been specified.
    end %DEPENDENT
	
%===================================================================================================
    properties (SetAccess = private, GetAccess = private) %                        P R I V A T E [P]
        pInfo;
        pInfoIndex;
        pFades;
        pFadesIndex;
        pLoadFile;          % Specifies the file name, including full path, to      string
                            %   the loaded data object.
        pFileData;          % Structure of data arrays used to store data that      struct
                            %   was loaded from a file instead of generated by
                            %   the initializer class.
    end %PROTECTED
	
	
	
	
	
%===================================================================================================
    methods %																	  G E T / S E T  [M]
		
%___________________________________________________________________________________________________ Initializer
		function obj = Initializer()
            obj.pInfo                = cell(1,100);
            obj.pInfoIndex           = 1;
            obj.pFadesIndex          = 1;
            obj.mode.fluid           = true;
            obj.mode.magnet          = false;
            obj.mode.gravity         = false;
            obj.debug                = false;
            obj.gamma                = 5/3;
            obj.iterMax              = 10;
            obj.minMass              = 1e-5;
            obj.ppSave.dim1          = 10;
            obj.ppSave.dim2          = 25;
            obj.ppSave.dim3          = 50;
            obj.ppSave.cust          = 50;
            obj.profile              = false;
            obj.save                 = true;
            obj.thresholdMass        = 0;
            obj.timeMax              = 1e5;
            obj.wallMax              = 1e5;
            obj.treadmill            = 0;
            obj.timeUpdateMode       = ENUM.TIMEUPDATE_PER_ITERATION;
            obj.gravity              = GravitySubInitializer();
            obj.viscosity            = ViscositySubInitializer();
            obj.radiation            = RadiationSubInitializer();
            obj.fluxLimiter          = struct();

            obj.useGPU               = false;
            obj.gpuDeviceNumber            = 0;

            fields = SaveManager.SLICEFIELDS;
            for i=1:length(fields)
                obj.activeSlices.(fields{i}) = false; 
            end
            
            obj.logProperties       = {'alias', 'grid'};
            
        end           

%___________________________________________________________________________________________________ GS: saveSlicesSpecified
        function result = get.saveSlicesSpecified(obj)
            s      = obj.activeSlices;
            result = s.x || s.y || s.z || s.xy || s.xz || s.yz || s.xyz;
        end
        
%___________________________________________________________________________________________________ GS: fades
        function result = get.fades(obj)
            if (obj.pFadesIndex < 2);  result = [];
            else                      result = obj.pFades(1:(obj.pFadesIndex-1));
            end
        end
        
%___________________________________________________________________________________________________ GS: info
        function result = get.info(obj)
            if isempty(obj.info); obj.info = 'Unspecified trial information.'; end
            result = ['---+ (' obj.runCode ') ' obj.info];
        end

%___________________________________________________________________________________________________ GS: image
        function result = get.image(obj)
            fields = ImageManager.FIELDS;
            if ~isempty(obj.image);     result = obj.image; end
            for i=1:length(fields)
               if isfield(obj.image,fields{i}); result.(fields{i}) = obj.image.(fields{i});
               else result.(fields{i}) = false;
               end
            end
            
            
            
        end
                
%___________________________________________________________________________________________________ GS: cfl        
        function result = get.cfl(obj)
           if isempty(obj.cfl)
               if obj.mode.magnet;      result = 0.35;
               else                     result = 0.7;
               end
           else result = obj.cfl;
           end
        end
        
%___________________________________________________________________________________________________ GS: bcMode     
        function result = get.bcMode(obj)
           if isempty(obj.bcMode)
                result.x = 'circ'; result.y = 'circ'; result.z = 'circ';
           else result = obj.bcMode;
           end
        end
        
%___________________________________________________________________________________________________ GS: bcInfinity
        function result = get.bcInfinity(obj)
            if isempty(obj.bcInfinity)
                result = 20;
            else result = obj.bcInfinity;
            end
        end
        
%___________________________________________________________________________________________________ GS: grid
        function set.grid(obj,value)
            obj.grid = Initializer.make3D(value, 1);
        end
        
%___________________________________________________________________________________________________ GS: fluxLimiter
        function result = get.fluxLimiter(obj)
            result = struct();
            fields = {'x', 'y', 'z'};
            for i=1:3
                if isfield(obj.fluxLimiter, fields{i})
                    result.(fields{i}) = obj.fluxLimiter.(fields{i});
                else
                    result.(fields{i}) = FluxLimiterEnum.VAN_LEER;
                end
            end
        end

	end%GET/SET
	
%===================================================================================================
    methods (Access = public) %														P U B L I C  [M]
			
%___________________________________________________________________________________________________ operateOnInput
        function operateOnInput(obj, input, defaultGrid)
            if isempty(input)
                obj.grid        = defaultGrid;
                
            elseif isnumeric(input)
                obj.grid        = input;
                
            elseif ischar(input)
                obj.pLoadFile   = input;
                obj.loadDataFromFile(input);
            end
        end
        
%___________________________________________________________________________________________________ getInitialConditions
		function [mass, mom, ener, mag, statics, run] = getInitialConditions(obj)
            if ~isempty(obj.pLoadFile)
                mass    = obj.pFileData.mass;
                mom     = obj.pFileData.mom;
                ener    = obj.pFileData.ener;
                mag     = obj.pFileData.mag;
                statics = [];
            else
                [mass, mom, ener, mag, statics] = obj.calculateInitialConditions();
            end
            
            if isempty(obj.slice)
                obj.slice = ceil(obj.grid/2);
            end
            run = obj.getRunSettings();
        end

%___________________________________________________________________________________________________ getRunSettings
        function result = getRunSettings(obj)

            %--- Populate skips cell array ---%
            %       Specific fields are skipped from being included in the initialization structure.
            %       This includes any field that is named in all CAPITAL LETTERS.
            fields = fieldnames(obj);
            skips  = {};
            for i=1:length(fields)
                if (strcmp(upper(fields{i}),fields{i}))
                    skips{length(skips) + 1} = fields{i};
                end
            end
            
            obj.cleanup();
            result          = Initializer.parseValues(obj, skips);
            result.iniInfo  = obj.getInfo();
        end
        
%___________________________________________________________________________________________________ addFade
% Adds a fade object to the run.
        function addFade(obj, location, fadeSize, fadeType, fadeFluxes, activeList)
            index                       = obj.pFadesIndex;
            obj.pFades(index).location  = location;
            obj.pFades(index).size      = fadeSize;
            obj.pFades(index).type      = fadeType;
            obj.pFades(index).active    = activeList;
            obj.pFades(index).fluxes    = fadeFluxes;
            obj.pFadesIndex = index + 1;
        end
        
	end%PUBLIC
	
%===================================================================================================	
	methods (Access = protected) %											P R O T E C T E D    [M]
   

        
%___________________________________________________________________________________________________ calculateInitialConditions
% Calculates all of the initial conditions for the run and returns a simplified structure containing
% all of the initialization property settings for the run.
        function [mass, mom, ener, mag, statics, run] = calculateInitialConditions(obj)
            %%%% Must be implemented in subclasses %%%%
        end
    
%___________________________________________________________________________________________________ loadDataFromFile
        function loadDataFromFile(obj, filePathToLoad)
            if isempty(filePathToLoad); return; end
            
            path                        = fileparts(filePathToLoad);
            data                        = load(filePathToLoad);
            fields                      = fieldnames(data);
            obj.pFileData.mass          = data.(fields{1}).mass;
            obj.pFileData.ener          = data.(fields{1}).ener;
            obj.pFileData.mom           = zeros([3, size(obj.pFileData.mass)]);
            obj.pFileData.mom(1,:,:,:)  = data.(fields{1}).momX;
            obj.pFileData.mom(2,:,:,:)  = data.(fields{1}).momY;
            obj.pFileData.mom(3,:,:,:)  = data.(fields{1}).momZ;
            obj.pFileData.mag           = zeros([3, size(obj.pFileData.mass)]);
            if ~isempty(data.(fields{1}).magX)
                obj.pFileData.mag(1,:,:,:)  = data.(fields{1}).magX;
                obj.pFileData.mag(2,:,:,:)  = data.(fields{1}).magY;
                obj.pFileData.mag(3,:,:,:)  = data.(fields{1}).magZ;
            end
            
            clear('data');
            
            ini  = load([path filesep 'ini_settings.mat']);
            obj.populateValues(ini.ini);
        end
        
        
%___________________________________________________________________________________________________ getInfo
% Gets the information string
        function result = getInfo(obj)
            
            %--- Populate skips cell array ---%
            %       Specific fields are skipped from being included in the initialization structure.
            %       This includes any field that is named in all CAPITAL LETTERS.
            fields = fieldnames(obj);
            skips  = {'info', 'runCode'};
            for i=1:length(fields)
                if (strcmp(upper(fields{i}),fields{i}))
                    skips{length(skips) + 1} = fields{i};
                end
            end
            
            result = '';
            for i=1:length(obj.pInfo)
                if isempty(obj.pInfo{i}); break; end
                result = strcat(result,sprintf('\n   * %s',obj.pInfo{i}));
            end
            
           result = [result '\n   * Intialized settings:' ...
                    ImogenRecord.valueToString(obj, skips, 1)];
        end		
		
%___________________________________________________________________________________________________ cleanup
% Fills in any critical missing information that was not filled in by the user and could not be set
% during Initializer class construction.
        function cleanup(obj)
            
            %--- Populate activeSlices structure if nothing was supplied. ---%
            if all(cell2mat(struct2cell(obj.activeSlices)))
                slLabels = SaveManager.SLICEFIELDS;
                [maxVal, maxInd] = max(obj.grid);
                obj.activeSlices.(slLabels{maxInd}) = true;
                [minVal, minInd] = min(obj.grid); 
                midInd = find((1:3 ~= maxInd(1)) & (1:3 ~= minInd(1)));
                if obj.grid(midInd) > 3
                    obj.activeSlices.(slLabels{midInd+3}) = true;
                end
                if ~isempty(obj.customSave);    obj.activeSlices.cust = true; end
            end 
            
        end
        
%___________________________________________________________________________________________________ appendInfo
% Adds argument string to the info string list for inclusion in the iniInfo property. A good way
% to store additional information about a run.
        function appendInfo(obj, infoStr, varargin)
            if ~isempty(varargin)
                evalStr = ['sprintf(''' infoStr ''''];
                for i=1:length(varargin)
                   evalStr = strcat(evalStr, ',varargin{', num2str(i), '}');
                end
                evalStr = strcat(evalStr,');');
                infoStr = eval(evalStr);
            end
            obj.pInfo{obj.pInfoIndex} = infoStr;
            obj.pInfoIndex = obj.pInfoIndex + 1;
        end
        
%___________________________________________________________________________________________________ populateValues
        function populateValues(obj, loadedInput, inputFields)
            if (nargin < 3 || isempty(inputFields)); inputFields = {}; end
            fields  = fieldnames(getfield(loadedInput, {1}, inputFields{:}, {1}));
            values  = getfield(loadedInput, {1}, inputFields{:}, {1});
            inLen   = length(inputFields);
            
            for i=1:length(fields)
                newInputFields              = inputFields;
                newInputFields{inLen + 1}   = fields{i};
                if  strcmp('fades', fields{i})
                    obj.pFades      = values.fades;
                    obj.pFadesIndex = length(obj.pFades) + 1;
                elseif  isstruct(values.(fields{i})) 
                    obj.populateValues(loadedInput, newInputFields);
                else
                    objFieldStr = 'obj';
                    for j=1:length(newInputFields)
                        objFieldStr = strcat(objFieldStr, '.', newInputFields{j});
                    end
                    
                    try
                        eval([objFieldStr, ' = values.(fields{i});']);
                    catch MERR
                        if strcmp(upper(fields{i}), fields{i}); continue; end
                        if strcmp(fields{i}, 'iniInfo'); continue; end
                        
                        if strcmp(fields{i}, 'fades')
                            obj.pFades          = values.(fields{i});
                            obj.pFadesIndex     = length(obj.pFades);
                            continue;
                        end
                        
                        fprintf('\tWARNING: Unable to set value for "%s"\n',objFieldStr);
                    end
                end
            end
        end
        
	end%PROTECTED
		    
%===================================================================================================	
	methods (Static = true) %													  S T A T I C    [M]
		        
%___________________________________________________________________________________________________ parseValues
% Parses an object and returns a structure of corresponding fields and value pairs.
        function result = parseValues(objectToParse, skips)
            fields = fieldnames(objectToParse); 
            for i=1:length(fields)
                if any(strcmp(fields{i}, skips)); continue; end
                if isobject(objectToParse.(fields{i}))
                    result.(fields{i}) = Initializer.parseValues(objectToParse.(fields{i}), skips);
                else
                    result.(fields{i}) = objectToParse.(fields{i});
                end
            end
        end

%___________________________________________________________________________________________________ make3D
% Enforces the 3D nature of an input value, so that it has a value for each spatial component.
%>>	inputValue		value to make 3D, can be length 1,2, or 3.							double(?)
%>>	fill			value to use when one is missing in the inputValue.					double
%<< result			converted value to have 3 spatial components						double(3)
		function result = make3D(inputValue, fill)
			if nargin < 3 || isempty(fill);		fill = min(inputValue);		end
			inLen = length(inputValue);
			
			switch inLen
				case 1;		result = inputValue * ones(1,3);
				case 2;		result = [inputValue fill];				
				case 3;		result = inputValue;
			end
		end
	end%PROTECTED
	
end%CLASS
