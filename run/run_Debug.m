% Run a short loop test to make sure that the code will execute through an entire sequence.

%-- Initialize Imogen directory ---%
starterRun();

%--- Initialize test ---%
run                             = JetInitializer([128 32 1]);
run.iterMax                     = 15;
obj.backMags                    = [1 0 1]/(4*pi);
run.mode.gravity                = false;
run.mode.magnet                 = true;
run.thresholdMass               = 0.00456;
run.gamma                       = 5;
run.gravity.constant            = 1.01;
run.bcMode.x                    = {ENUM.BCMODE_CONST, ENUM.BCMODE_WALL};

run.viscosity.type              = ENUM.ARTIFICIAL_VISCOSITY_NEUMANN_RICHTMYER;
run.viscosity.linear            = 0.1;
run.viscosity.quadratic         = 0.25;

run.radiation.type              = ENUM.RADIATION_OPTICALLY_THIN;
run.radiation.exponent          = 0.5;
run.radiation.initialMaximum    = 0.1;

run.image.interval              = 1;
run.image.mass                  = true;
run.image.mach                  = true;

run.info                        = 'Debug test';
run.notes                       = '';

%--- Run tests ---%
if (true)
    [mass, mom, ener, magnet, statics, ini] = run.getInitialConditions();
    ini.runCode = 'Debug';
    imogen(mass, mom, ener, magnet, ini, statics);
end

enderRun();
