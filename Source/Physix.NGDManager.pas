//
// The graphics rendering engine GXScene  http://glscene.org
//
unit Physix.NGDManager;

(*
  A Newton Game Dynamics Manager for GXScene.
  Notes:
  This code is still under development so any part of it may change at anytime.
*)

interface

{$I GXScene.inc}

uses
  System.Classes, // TComponent Tlist TWriter TReader TPersistent
  System.SysUtils, //System utilities
  System.Math, // Samevalue isZero to compare single
  ImportX.Newton, // Newton
  ImportX.Newton_Joints,
  GXS.XCollection,  //TXCollection file function
  GXS.VectorGeometry, // PVector TVector TMatrix PMatrix NullHmgVector...
  GXS.VectorLists, // TaffineVectorList for Tree
  GXS.BaseClasses,
  GXS.Scene,
  GXS.Manager,
  GXS.Coordinates,
  GXS.Objects,
  GXS.GeomObjects,
  GXS.VectorFileObjects, // cube cone freeform...
  GXS.Color,
  GXS.GeometryBB; // For show debug

type
  NGDFloat = ImportX.Newton.Float;
  PNGDFloat = ^NGDFloat;

  TgxHeightField = record
    heightArray: array of Word;
    width: Integer;
    depth: Integer;
    gridDiagonals: Boolean;
    widthDepthScale: Single;
    heightScale: Single;
  end;

  TgxNGDBehaviour = class;
  TgxNGDManager = class;
  TNGDSurfaceItem = class;
  TNGDJoint = class;

  TNGDSolverModels = (smExact = 0, smLinear1, smLinear2, smLinear3, smLinear4,
    smLinear5, smLinear6, smLinear7, smLinear8, smLinear9);

  TNGDFrictionModels = (fmExact = 0, fmAdaptive);
  TNGDPickedActions = (paAttach = 0, paMove, paDetach);

  TNGDManagerDebug = (mdShowGeometry, mdShowAABB, mdShowCenterOfMass,
    mdShowContact, mdShowJoint, mdShowForce, mdShowAppliedForce,
    mdShowAppliedVelocity);
  TNGDManagerDebugs = set of TNGDManagerDebug;

  TNGDNewtonCollisions = (nc_Primitive = 0, nc_Convex, nc_BBox, nc_BSphere,
    nc_Tree, nc_Mesh, nc_Null, nc_HeightField, nc_NGDFile);

  TNGDNewtonJoints = (nj_BallAndSocket, nj_Hinge, nj_Slider, nj_Corkscrew,
    nj_Universal, nj_CustomBallAndSocket, nj_CustomHinge, nj_CustomSlider,
    nj_UpVector, nj_KinematicController);

  TgxNGDBehaviourList = class(TList)
  protected
    function GetBehav(index: Integer): TgxNGDBehaviour;
    procedure PutBehav(index: Integer; Item: TgxNGDBehaviour);
  public
    property ItemsBehav[index: Integer]
      : TgxNGDBehaviour read GetBehav write PutBehav; default;
  end;

  // Events for Newton Callback
  TCollisionIteratorEvent = procedure(const userData: Pointer;
    vertexCount: Integer; const cfaceArray: PNGDFloat;
    faceId: Integer) of object;

  TApplyForceAndTorqueEvent = procedure(const cbody: PNewtonBody;
    timestep: NGDFloat; threadIndex: Integer) of object;

  TSetTransformEvent = procedure(const cbody: PNewtonBody;
    const cmatrix: PNGDFloat; threadIndex: Integer) of object;

  TSerializeEvent = procedure(serializeHandle: Pointer; const cbuffer: Pointer;
    size: Cardinal) of object;

  TDeSerializeEvent = procedure(serializeHandle: Pointer; buffer: Pointer;
    size: Cardinal) of object;

  TAABBOverlapEvent = function(const cmaterial: PNewtonMaterial;
    const cbody0: PNewtonBody; const cbody1: PNewtonBody;
    threadIndex: Integer): Boolean of object;

  TContactProcessEvent = procedure(const ccontact: PNewtonJoint;
    timestep: NGDFloat; threadIndex: Integer) of object;

  TNGDDebugOption = class(TPersistent)
  strict private
    FManager: TgxNGDManager;
    FGeomColorDyn: TgxColor; // Green
    FGeomColorStat: TgxColor; // Red
    FAABBColor: TgxColor; // Yellow
    FAABBColorSleep: TgxColor; // Orange
    FCenterOfMassColor: TgxColor; // Purple dot
    FContactColor: TgxColor; // White
    FJointAxisColor: TgxColor; // Blue
    FJointPivotColor: TgxColor; // Aquamarine
    FForceColor: TgxColor; // Black
    FAppliedForceColor: TgxColor; // Silver
    FAppliedVelocityColor: TgxColor; // Lime
    FCustomColor: TgxColor; // Aqua
    FDotAxisSize: Single; // 1
    FNGDManagerDebugs: TNGDManagerDebugs; // Default All false
    procedure SetNGDManagerDebugs(const Value: TNGDManagerDebugs);
    procedure SetDotAxisSize(const Value: Single);
    function StoredDotAxis: Boolean;

  public
    constructor Create(AOwner: TComponent);
    destructor Destroy; override;

  published
    property GeomColorDyn: TgxColor read FGeomColorDyn write FGeomColorDyn;
    property GeomColorStat: TgxColor read FGeomColorStat write FGeomColorStat;
    property AABBColor: TgxColor read FAABBColor write FAABBColor;
    property AABBColorSleep: TgxColor read FAABBColorSleep write FAABBColorSleep;
    property CenterOfMassColor: TgxColor read FCenterOfMassColor write FCenterOfMassColor;
    property ContactColor: TgxColor read FContactColor write FContactColor;
    property JointAxisColor: TgxColor read FJointAxisColor write FJointAxisColor;
    property JointPivotColor: TgxColor read FJointPivotColor write FJointPivotColor;
    property ForceColor: TgxColor read FForceColor write FForceColor;
    property AppliedForceColor: TgxColor read FAppliedForceColor write FAppliedForceColor;
    property AppliedVelocityColor: TgxColor read FAppliedVelocityColor write FAppliedVelocityColor;
    property CustomColor: TgxColor read FCustomColor write FCustomColor;
    property NGDManagerDebugs: TNGDManagerDebugs read FNGDManagerDebugs write
      SetNGDManagerDebugs default[];
    property DotAxisSize: Single read FDotAxisSize write SetDotAxisSize stored
      StoredDotAxis;
  end;

  TgxNGDManager = class(TComponent)
  strict private
    FVisible: Boolean; // Show Debug at design time
    FVisibleAtRunTime: Boolean; // Show Debug at run time
    FDllVersion: Integer;
    FSolverModel: TNGDSolverModels; // Default=Exact
    FFrictionModel: TNGDFrictionModels; // Default=Exact
    FMinimumFrameRate: Integer; // Default=60
    FWorldSizeMin: TgxCoordinates; // Default=-100, -100, -100
    FWorldSizeMax: TgxCoordinates; // Default=100, 100, 100
    FThreadCount: Integer; // Default=1
    FGravity: TgxCoordinates; // Default=(0,-9.81,0)
    FNewtonSurfaceItem: TCollection;
    FNewtonSurfacePair: TOwnedCollection;
    FNewtonJointGroup: TOwnedCollection;
    FNGDDebugOption: TNGDDebugOption;
    FGLLines: TgxLines;
  private
    FNewtonWorld: PNewtonWorld;
    FNGDBehaviours: TgxNGDBehaviourList;
    FCurrentColor: TgxColor;
  protected
    procedure Loaded; override;
    procedure SetVisible(const Value: Boolean);
    procedure SetVisibleAtRunTime(const Value: Boolean);
    procedure SetSolverModel(const Value: TNGDSolverModels);
    procedure SetFrictionModel(const Value: TNGDFrictionModels);
    procedure SetMinimumFrameRate(const Value: Integer);
    procedure SetThreadCount(const Value: Integer);
    procedure SetLines(const Value: TgxLines);
    function GetBodyCount: Integer;
    function GetConstraintCount: Integer;
    procedure AddNode(const coords: TgxCustomCoordinates); overload;
    procedure AddNode(const X, Y, Z: Single); overload;
    procedure AddNode(const Value: TVector); overload;
    procedure AddNode(const Value: TAffineVector); overload;
    procedure RebuildAllMaterial;
    procedure RebuildAllJoint(Sender: TObject);
    // Events
    procedure NotifyWorldSizeChange(Sender: TObject);
    procedure NotifyChange(Sender: TObject); // Debug view
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Step(deltatime: Single);
  published
    property Visible: Boolean read FVisible write SetVisible default True;
    property VisibleAtRunTime: Boolean read FVisibleAtRunTime write
      SetVisibleAtRunTime default False;
    property SolverModel: TNGDSolverModels read FSolverModel write
      SetSolverModel default smExact;
    property FrictionModel: TNGDFrictionModels read FFrictionModel write
      SetFrictionModel default fmExact;
    property MinimumFrameRate: Integer read FMinimumFrameRate write
      SetMinimumFrameRate default 60;
    property ThreadCount
      : Integer read FThreadCount write SetThreadCount default 1;
    property DllVersion: Integer read FDllVersion;
    property NewtonBodyCount: Integer read GetBodyCount;
    property NewtonConstraintCount: Integer read GetConstraintCount;
    property Gravity: TgxCoordinates read FGravity write FGravity;
    property WorldSizeMin
      : TgxCoordinates read FWorldSizeMin write FWorldSizeMin;
    property WorldSizeMax
      : TgxCoordinates read FWorldSizeMax write FWorldSizeMax;
    property NewtonSurfaceItem
      : TCollection read FNewtonSurfaceItem write FNewtonSurfaceItem;
    property NewtonSurfacePair: TOwnedCollection read FNewtonSurfacePair write
      FNewtonSurfacePair;
    property DebugOption: TNGDDebugOption read FNGDDebugOption write
      FNGDDebugOption;
    property Line: TgxLines read FGLLines write SetLines;
    property NewtonJoint: TOwnedCollection read FNewtonJointGroup write
      FNewtonJointGroup;
  end;

  // Basis structures for behaviour style implementations.
  TgxNGDBehaviour = class(TgxBehaviour)
  private
    FManager: TgxNGDManager;
    FManagerName: string;
    FInitialized: Boolean;
    FNewtonBody: PNewtonBody;
    FCollision: PNewtonCollision;
    FNewtonBodyMatrix: TMatrix; // Position and Orientation
    FContinuousCollisionMode: Boolean; // Default=False
    FNGDNewtonCollisions: TNGDNewtonCollisions;
    FCollisionIteratorEvent: TCollisionIteratorEvent;
    FOwnerBaseSceneObject: TgxBaseSceneObject;
    // FNullCollisionMass: Single; // Default=0
    FTreeCollisionOptimize: Boolean; // Default=True
    FConvexCollisionTolerance: Single; // Default=0.01 1%
    FFileCollision: string;
    FNGDSurfaceItem: TNGDSurfaceItem;
    FHeightFieldOptions: TgxHeightField;
  protected
    procedure Initialize; virtual;
    procedure Finalize; virtual;
    procedure WriteToFiler(writer: TWriter); override;
    procedure ReadFromFiler(reader: TReader); override;
    procedure Loaded; override;
    procedure SetManager(Value: TgxNGDManager);
    procedure SetNewtonBodyMatrix(const Value: TMatrix);
    procedure SetContinuousCollisionMode(const Value: Boolean);
    function GetNewtonBodyMatrix: TMatrix;
    function GetNewtonBodyAABB: TAABB;
    procedure UpdCollision; virtual;
    procedure Render; virtual;
    procedure SetNGDNewtonCollisions(const Value: TNGDNewtonCollisions);
    procedure SetNGDSurfaceItem(const Value: TNGDSurfaceItem);
    procedure SetHeightFieldOptions(const Value: TgxHeightField);
    function GetPrimitiveCollision(): PNewtonCollision;
    function GetConvexCollision(): PNewtonCollision;
    function GetBBoxCollision(): PNewtonCollision;
    function GetBSphereCollision(): PNewtonCollision;
    function GetTreeCollision(): PNewtonCollision;
    function GetMeshCollision(): PNewtonCollision;
    function GetNullCollision(): PNewtonCollision;
    function GetHeightFieldCollision(): PNewtonCollision;
    function GetNGDFileCollision(): PNewtonCollision;
    function StoredTolerance: Boolean;
    // Event
    procedure OnCollisionIteratorEvent(const userData: Pointer;
      vertexCount: Integer; const cfaceArray: PNGDFloat; faceId: Integer);
    // CallBack
    class procedure NewtonCollisionIterator(const userData: Pointer;
      vertexCount: Integer; const faceArray: PNGDFloat;
      faceId: Integer); static; cdecl;
    class procedure NewtonSerialize(serializeHandle: Pointer;
      const buffer: Pointer; size: Cardinal); static; cdecl;
    class procedure NewtonDeserialize(serializeHandle: Pointer;
      buffer: Pointer; size: Cardinal); static; cdecl;
  public
    constructor Create(AOwner: TXCollection); override;
    destructor Destroy; override;
    procedure Reinitialize;
    property Initialized: Boolean read FInitialized;
    class function UniqueItem: Boolean; override;
    property NewtonBodyMatrix: TMatrix read GetNewtonBodyMatrix write
      SetNewtonBodyMatrix;
    property NewtonBodyAABB: TAABB read GetNewtonBodyAABB;
    procedure Serialize(filename: string);
    procedure DeSerialize(filename: string);
    property HeightFieldOptions: TgxHeightField read FHeightFieldOptions write
      SetHeightFieldOptions;
  published
    property Manager: TgxNGDManager read FManager write SetManager;
    property ContinuousCollisionMode
      : Boolean read FContinuousCollisionMode write
      SetContinuousCollisionMode default False;
    property NGDNewtonCollisions
      : TNGDNewtonCollisions read FNGDNewtonCollisions
      write SetNGDNewtonCollisions default nc_Primitive;
    property TreeCollisionOptimize: Boolean read FTreeCollisionOptimize write
      FTreeCollisionOptimize default True;
    property ConvexCollisionTolerance
      : Single read FConvexCollisionTolerance write
      FConvexCollisionTolerance stored StoredTolerance;
    property FileCollision: string read FFileCollision write FFileCollision;
    property NGDSurfaceItem: TNGDSurfaceItem read FNGDSurfaceItem write
      SetNGDSurfaceItem;
  end;

  TgxNGDDynamic = class(TgxNGDBehaviour)
  strict private
    FAABBmin: TgxCoordinates;
    FAABBmax: TgxCoordinates;
    FForce: TgxCoordinates;
    FTorque: TgxCoordinates;
    FCenterOfMass: TgxCoordinates;
    FAutoSleep: Boolean; // Default=True
    FLinearDamping: Single; // default=0.1
    FAngularDamping: TgxCoordinates; // Default=0.1
    FDensity: Single; // Default=1
    FUseGravity: Boolean; // Default=True
    FNullCollisionVolume: Single; // Default=0
    FApplyForceAndTorqueEvent: TApplyForceAndTorqueEvent;
    FSetTransformEvent: TSetTransformEvent;
    FCustomForceAndTorqueEvent: TApplyForceAndTorqueEvent;
    // Read Only
    FVolume: Single;
    FMass: Single;
    FAppliedForce: TgxCoordinates;
    FAppliedTorque: TgxCoordinates;
    FAppliedOmega: TgxCoordinates;
    FAppliedVelocity: TgxCoordinates;
    function StoredDensity: Boolean;
    function StoredLinearDamping: Boolean;
    function StoredNullCollisionVolume: Boolean;
  protected
    procedure SetAutoSleep(const Value: Boolean);
    procedure SetLinearDamping(const Value: Single);
    procedure SetDensity(const Value: Single); virtual;
    procedure Initialize; override;
    procedure Finalize; override;
    procedure WriteToFiler(writer: TWriter); override;
    procedure ReadFromFiler(reader: TReader); override;
    procedure Loaded; override;
    procedure Render; override;
    // Events
    procedure NotifyCenterOfMassChange(Sender: TObject);
    procedure NotifyAngularDampingChange(Sender: TObject);
    procedure OnApplyForceAndTorqueEvent(const cbody: PNewtonBody;
      timestep: NGDFloat; threadIndex: Integer);
    procedure OnSetTransformEvent(const cbody: PNewtonBody;
      const cmatrix: PNGDFloat; threadIndex: Integer);
    // Callback
    class procedure NewtonApplyForceAndTorque(const body: PNewtonBody;
      timestep: NGDFloat; threadIndex: Integer); static; cdecl;
    class procedure NewtonSetTransform(const body: PNewtonBody;
      const matrix: PNGDFloat; threadIndex: Integer); static; cdecl;
  public
    constructor Create(AOwner: TXCollection); override;
    destructor Destroy; override;
    procedure AddImpulse(const veloc, pointposit: TVector);
    function GetOmega: TVector;
    procedure SetOmega(const Omega: TVector);
    function GetVelocity: TVector;
    procedure SetVelocity(const Velocity: TVector);
    class function FriendlyName: string; override;
    property CustomForceAndTorqueEvent
      : TApplyForceAndTorqueEvent read FCustomForceAndTorqueEvent write
      FCustomForceAndTorqueEvent;
  published
    property Force: TgxCoordinates read FForce write FForce;
    property Torque: TgxCoordinates read FTorque write FTorque;
    property Velocity: TVector read GetVelocity write SetVelocity;
    property Omega: TVector read GetOmega write SetOmega;
    property CenterOfMass: TgxCoordinates read FCenterOfMass write FCenterOfMass;
    property AutoSleep: Boolean read FAutoSleep write SetAutoSleep default True;
    property LinearDamping: Single read FLinearDamping write SetLinearDamping
      stored StoredLinearDamping;
    property AngularDamping: TgxCoordinates read FAngularDamping write FAngularDamping;
    property Density: Single read FDensity write SetDensity stored StoredDensity;
    property UseGravity: Boolean read FUseGravity write FUseGravity default True;
    property NullCollisionVolume: Single read FNullCollisionVolume write FNullCollisionVolume stored
      StoredNullCollisionVolume;
    // Read Only
    property AppliedOmega: TgxCoordinates read FAppliedOmega;
    property AppliedVelocity: TgxCoordinates read FAppliedVelocity;
    property AppliedForce: TgxCoordinates read FAppliedForce;
    property AppliedTorque: TgxCoordinates read FAppliedTorque;
    property Volume: Single read FVolume;
    property Mass: Single read FMass;
  end;

  TgxNGDStatic = class(TgxNGDBehaviour)
  protected
    procedure Render; override;
  public
    class function FriendlyName: string; override;
  published
  end;

  TNGDSurfaceItem = class(TCollectionItem)
  private
    FDisplayName: string;
  protected
    function GetDisplayName: string; override;
    procedure SetDisplayName(const Value: string); override;

  published
    property DisplayName;
    property ID;
  end;

  TNGDSurfacePair = class(TCollectionItem)
  strict private
    FManager: TgxNGDManager;
    FNGDSurfaceItem1: TNGDSurfaceItem;
    FNGDSurfaceItem2: TNGDSurfaceItem;
    FAABBOverlapEvent: TAABBOverlapEvent;
    FContactProcessEvent: TContactProcessEvent;
    FSoftness: Single; // 0.1
    FElasticity: Single; // 0.4
    FCollidable: Boolean; // true
    FStaticFriction: Single; // 0.9
    FKineticFriction: Single; // 0.5
    FContinuousCollisionMode: Boolean; // False
    FThickness: Boolean; // False
    procedure SetCollidable(const Value: Boolean);
    procedure SetElasticity(const Value: Single);
    procedure SetKineticFriction(const Value: Single);
    procedure SetSoftness(const Value: Single);
    procedure SetStaticFriction(const Value: Single);
    procedure SetContinuousCollisionMode(const Value: Boolean);
    procedure SetThickness(const Value: Boolean);
    function StoredElasticity: Boolean;
    function StoredKineticFriction: Boolean;
    function StoredSoftness: Boolean;
    function StoredStaticFriction: Boolean;
  private
    // Callback
    class function NewtonAABBOverlap(const material: PNewtonMaterial;
      const body0: PNewtonBody; const body1: PNewtonBody;
      threadIndex: Integer): Integer; static; cdecl;
    class procedure NewtonContactsProcess(const contact: PNewtonJoint;
      timestep: NGDFloat; threadIndex: Integer); static; cdecl;
    // Event
    function OnNewtonAABBOverlapEvent(const cmaterial: PNewtonMaterial;
      const cbody0: PNewtonBody; const cbody1: PNewtonBody;
      threadIndex: Integer): Boolean;
    procedure OnNewtonContactsProcessEvent(const ccontact: PNewtonJoint;
      timestep: NGDFloat; threadIndex: Integer);
  public
    constructor Create(Collection: TCollection); override;
    procedure SetMaterialItems(const item1, item2: TNGDSurfaceItem);
    property NGDSurfaceItem1: TNGDSurfaceItem read FNGDSurfaceItem1;
    property NGDSurfaceItem2: TNGDSurfaceItem read FNGDSurfaceItem2;
  published
    property Softness: Single read FSoftness write SetSoftness stored
      StoredSoftness;
    property Elasticity: Single read FElasticity write SetElasticity stored
      StoredElasticity;
    property Collidable: Boolean read FCollidable write SetCollidable default True;
    property StaticFriction: Single read FStaticFriction write SetStaticFriction
      stored StoredStaticFriction;
    property KineticFriction: Single read FKineticFriction write SetKineticFriction stored
      StoredKineticFriction;
    property ContinuousCollisionMode: Boolean read FContinuousCollisionMode write
      SetContinuousCollisionMode default False;
    property Thickness: Boolean read FThickness write SetThickness default False;
    property ContactProcessEvent: TContactProcessEvent read FContactProcessEvent
      write FContactProcessEvent;
    property AABBOverlapEvent: TAABBOverlapEvent read FAABBOverlapEvent write
      FAABBOverlapEvent;
  end;

  TNGDJointPivot = class(TPersistent)
  private
    FManager: TgxNGDManager;
    FPivotPoint: TgxCoordinates;
    FOuter: TNGDJoint;
  public
    constructor Create(AOwner: TComponent; aOuter: TNGDJoint); virtual;
    destructor Destroy; override;
  published
    property PivotPoint: TgxCoordinates read FPivotPoint write FPivotPoint;
  end;

  TNGDJointPin = class(TNGDJointPivot)
  private
    FPinDirection: TgxCoordinates;
  public
    constructor Create(AOwner: TComponent; aOuter: TNGDJoint); override;
    destructor Destroy; override;
  published
    property PinDirection: TgxCoordinates read FPinDirection write FPinDirection;
  end;

  TNGDJointPin2 = class(TNGDJointPin)
  private
    FPinDirection2: TgxCoordinates;
  public
    constructor Create(AOwner: TComponent; aOuter: TNGDJoint); override;
    destructor Destroy; override;
  published
    property PinDirection2: TgxCoordinates read FPinDirection2 write FPinDirection2;
  end;

  TNGDJointBallAndSocket = class(TNGDJointPivot)
  private
    FConeAngle: Single; // 90
    FMinTwistAngle: Single; // -90
    FMaxTwistAngle: Single; // 90
    procedure SetConeAngle(const Value: Single);
    procedure SetMaxTwistAngle(const Value: Single);
    procedure SetMinTwistAngle(const Value: Single);
    function StoredMaxTwistAngle: Boolean;
    function StoredMinTwistAngle: Boolean;
    function StoredConeAngle: Boolean;
  public
    constructor Create(AOwner: TComponent; aOuter: TNGDJoint); override;
  published
    property ConeAngle: Single read FConeAngle write SetConeAngle stored
      StoredConeAngle;
    property MinTwistAngle
      : Single read FMinTwistAngle write SetMinTwistAngle
      stored StoredMinTwistAngle;
    property MaxTwistAngle
      : Single read FMaxTwistAngle write SetMaxTwistAngle
      stored StoredMaxTwistAngle;
  end;

  TNGDJointHinge = class(TNGDJointPin)
  private
    FMinAngle: Single; // -90
    FMaxAngle: Single; // 90
    procedure SetMaxAngle(const Value: Single);
    procedure SetMinAngle(const Value: Single);
    function StoredMaxAngle: Boolean;
    function StoredMinAngle: Boolean;
  public
    constructor Create(AOwner: TComponent; aOuter: TNGDJoint); override;
  published
    property MinAngle: Single read FMinAngle write SetMinAngle stored
      StoredMinAngle;
    property MaxAngle: Single read FMaxAngle write SetMaxAngle stored
      StoredMaxAngle;
  end;

  TNGDJointSlider = class(TNGDJointPin)
  private
    FMinDistance: Single; // -10
    FMaxDistance: Single; // 10
    procedure SetMaxDistance(const Value: Single);
    procedure SetMinDistance(const Value: Single);
    function StoredMaxDistance: Boolean;
    function StoredMinDistance: Boolean;
  public
    constructor Create(AOwner: TComponent; aOuter: TNGDJoint); override;
  published
    property MinDistance: Single read FMinDistance write SetMinDistance stored
	   StoredMinDistance;
    property MaxDistance: Single read FMaxDistance write SetMaxDistance stored
	   StoredMaxDistance;
  end;

  TNGDJointKinematicController = class(TPersistent)
  private
    FPickModeLinear: Boolean; // False
    FLinearFriction: Single; // 750
    FAngularFriction: Single; // 250
    function StoredAngularFriction: Boolean;
    function StoredLinearFriction: Boolean;
  public
    constructor Create();
  published
    property PickModeLinear
      : Boolean read FPickModeLinear write FPickModeLinear
      default False;
    property LinearFriction
      : Single read FLinearFriction write FLinearFriction stored
      StoredLinearFriction;
    property AngularFriction
      : Single read FAngularFriction write FAngularFriction stored
      StoredAngularFriction;
  end;

  TNGDJoint = class(TCollectionItem)
  private
    // Global
    FManager: TgxNGDManager;
    FParentObject: TgxBaseSceneObject;
    FJointType: TNGDNewtonJoints;
    FStiffness: Single; // 0.9
    { With Two object: every joint except nj_UpVector and nj_KinematicController}
    FChildObject: TgxBaseSceneObject;
    FCollisionState: Boolean; // False
    { With classic joint
     nj_BallAndSocket, nj_Hinge, nj_Slider, nj_Corkscrew
     nj_Universal, nj_UpVector }
    FNewtonJoint: PNewtonJoint;
    { With CustomJoint
     nj_CustomBallAndSocket, nj_CustomHinge, nj_CustomSlider
     nj_KinematicController }
    FNewtonUserJoint: Pointer;
    { nj_UpVector}
    FUPVectorDirection: TgxCoordinates;
    FBallAndSocketOptions: TNGDJointPivot;
    FHingeOptions: TNGDJointPin;
    FSliderOptions: TNGDJointPin;
    FCorkscrewOptions: TNGDJointPin;
    FUniversalOptions: TNGDJointPin2;
    FCustomBallAndSocketOptions: TNGDJointBallAndSocket;
    FCustomHingeOptions: TNGDJointHinge;
    FCustomSliderOptions: TNGDJointSlider;
    FKinematicOptions: TNGDJointKinematicController;
    procedure SetJointType(const Value: TNGDNewtonJoints);
    procedure SetChildObject(const Value: TgxBaseSceneObject);
    procedure SetCollisionState(const Value: Boolean);
    procedure SetParentObject(const Value: TgxBaseSceneObject);
    procedure SetStiffness(const Value: Single);
    procedure Render;
    function StoredStiffness: Boolean;
    procedure DestroyNewtonData;
  public
    constructor Create(Collection: TCollection); override;
    destructor Destroy; override;
    procedure KinematicControllerPick(pickpoint: TVector;
      PickedActions: TNGDPickedActions);
  published
    property BallAndSocketOptions
      : TNGDJointPivot read FBallAndSocketOptions write
      FBallAndSocketOptions;
    property HingeOptions: TNGDJointPin read FHingeOptions write FHingeOptions;
    property SliderOptions
      : TNGDJointPin read FSliderOptions write FSliderOptions;
    property CorkscrewOptions
      : TNGDJointPin read FCorkscrewOptions write FCorkscrewOptions;
    property UniversalOptions
      : TNGDJointPin2 read FUniversalOptions write FUniversalOptions;
    property CustomBallAndSocketOptions
      : TNGDJointBallAndSocket read FCustomBallAndSocketOptions write
      FCustomBallAndSocketOptions;
    property CustomHingeOptions: TNGDJointHinge read FCustomHingeOptions write
      FCustomHingeOptions;
    property CustomSliderOptions
      : TNGDJointSlider read FCustomSliderOptions write
      FCustomSliderOptions;
    property KinematicControllerOptions
      : TNGDJointKinematicController read FKinematicOptions write
      FKinematicOptions;
    property JointType: TNGDNewtonJoints read FJointType write SetJointType;
    property ParentObject: TgxBaseSceneObject read FParentObject write
      SetParentObject;
    property ChildObject: TgxBaseSceneObject read FChildObject write
      SetChildObject;
    property CollisionState
      : Boolean read FCollisionState write SetCollisionState default False;
    property Stiffness: Single read FStiffness write SetStiffness stored
      StoredStiffness;
    property UPVectorDirection
      : TgxCoordinates read FUPVectorDirection write FUPVectorDirection;
  end;

  { Global function }
function GetNGDStatic(Obj: TgxBaseSceneObject): TgxNGDStatic;
function GetOrCreateNGDStatic(Obj: TgxBaseSceneObject): TgxNGDStatic;
function GetNGDDynamic(Obj: TgxBaseSceneObject): TgxNGDDynamic;
function GetOrCreateNGDDynamic(Obj: TgxBaseSceneObject): TgxNGDDynamic;
function GetBodyFromGXSceneObject(Obj: TgxBaseSceneObject): PNewtonBody;

//=======================================================================
implementation
//=======================================================================

const
  epsilon = 0.0000001; // 1E-07

function GetNGDStatic(Obj: TgxBaseSceneObject): TgxNGDStatic;
begin
  Result := TgxNGDStatic(Obj.Behaviours.GetByClass(TgxNGDStatic));
end;

function GetOrCreateNGDStatic(Obj: TgxBaseSceneObject): TgxNGDStatic;
begin
  Result := TgxNGDStatic(Obj.GetOrCreateBehaviour(TgxNGDStatic));
end;

function GetNGDDynamic(Obj: TgxBaseSceneObject): TgxNGDDynamic;
begin
  Result := TgxNGDDynamic(Obj.Behaviours.GetByClass(TgxNGDDynamic));
end;

function GetOrCreateNGDDynamic(Obj: TgxBaseSceneObject): TgxNGDDynamic;
begin
  Result := TgxNGDDynamic(Obj.GetOrCreateBehaviour(TgxNGDDynamic));
end;

function GetBodyFromGXSceneObject(Obj: TgxBaseSceneObject): PNewtonBody;
var
  Behaviour: TgxNGDBehaviour;
begin
  Behaviour := TgxNGDBehaviour(Obj.Behaviours.GetByClass(TgxNGDBehaviour));
  Assert(Behaviour <> nil, 'NGD Behaviour (static or dynamic) is missing for this object');
  Result := Behaviour.FNewtonBody;
end;

// ------------------------------------------------------------------
//-------- TNGDDebugOption
// ------------------------------------------------------------------

constructor TNGDDebugOption.Create(AOwner: TComponent);
begin
  FManager := AOwner as TgxNGDManager;
  with FManager do
  begin
    FGeomColorDyn := TgxColor.CreateInitialized(self, clrGreen, NotifyChange);
    FGeomColorStat := TgxColor.CreateInitialized(self, clrRed, NotifyChange);
    FAABBColor := TgxColor.CreateInitialized(self, clrYellow, NotifyChange);
    FAABBColorSleep := TgxColor.CreateInitialized(self, clrOrange,
      NotifyChange);
    FCenterOfMassColor := TgxColor.CreateInitialized(self, clrPurple,
      NotifyChange);
    FContactColor := TgxColor.CreateInitialized(self, clrWhite, NotifyChange);
    FJointAxisColor := TgxColor.CreateInitialized(self, clrBlue, NotifyChange);
    FJointPivotColor := TgxColor.CreateInitialized(self, clrAquamarine,
      NotifyChange);

    FForceColor := TgxColor.CreateInitialized(self, clrBlack, NotifyChange);
    FAppliedForceColor := TgxColor.CreateInitialized(self, clrSilver,
      NotifyChange);
    FAppliedVelocityColor := TgxColor.CreateInitialized(self, clrLime,
      NotifyChange);

    FCustomColor := TgxColor.CreateInitialized(self, clrAqua, NotifyChange);
  end;
  FDotAxisSize := 1;
  FNGDManagerDebugs := [];

  FManager := AOwner as TgxNGDManager;
end;

destructor TNGDDebugOption.Destroy;
begin
  FGeomColorDyn.Free;
  FGeomColorStat.Free;
  FAABBColor.Free;
  FAABBColorSleep.Free;
  FCenterOfMassColor.Free;
  FContactColor.Free;
  FJointAxisColor.Free;
  FJointPivotColor.Free;
  FForceColor.Free;
  FAppliedForceColor.Free;
  FAppliedVelocityColor.Free;
  FCustomColor.Free;
  inherited;
end;

procedure TNGDDebugOption.SetDotAxisSize(const Value: Single);
begin
  FDotAxisSize := Value;
  FManager.NotifyChange(self);
end;

procedure TNGDDebugOption.SetNGDManagerDebugs(const Value: TNGDManagerDebugs);
begin
  FNGDManagerDebugs := Value;
  FManager.NotifyChange(self);
end;

function TNGDDebugOption.StoredDotAxis: Boolean;
begin
  Result := not SameValue(FDotAxisSize, 1, epsilon);
end;

// ------------------------------------------------------------------
{ TgxNGDManager }
// ------------------------------------------------------------------
procedure TgxNGDManager.AddNode(const Value: TVector);
begin
  if Assigned(FGLLines) then
  begin
    FGLLines.Nodes.AddNode(Value);

    with (FGLLines.Nodes.Last as TgxLinesNode) do
      Color := FCurrentColor;
  end;
end;

procedure TgxNGDManager.AddNode(const coords: TgxCustomCoordinates);
begin
  if Assigned(FGLLines) then
  begin
    FGLLines.Nodes.AddNode(coords); (FGLLines.Nodes.Last as TgxLinesNode)
    .Color := FCurrentColor;
  end;
end;

procedure TgxNGDManager.AddNode(const X, Y, Z: Single);
begin
  if Assigned(FGLLines) then
  begin
    FGLLines.Nodes.AddNode(X, Y, Z); (FGLLines.Nodes.Last as TgxLinesNode)
    .Color := FCurrentColor;
  end;
end;

procedure TgxNGDManager.AddNode(const Value: TAffineVector);
begin
  if Assigned(FGLLines) then
  begin
    FGLLines.Nodes.AddNode(Value); (FGLLines.Nodes.Last as TgxLinesNode)
    .Color := FCurrentColor;
  end;
end;

constructor TgxNGDManager.Create(AOwner: TComponent);
var
  minworld, maxworld: TVector;
begin
  inherited;
  FNGDBehaviours := TgxNGDBehaviourList.Create;
  FVisible := True;
  FVisibleAtRunTime := False;
  FSolverModel := smExact;
  FFrictionModel := fmExact;
  FMinimumFrameRate := 60;
  FWorldSizeMin := TgxCoordinates.CreateInitialized(self,
    VectorMake(-100, -100, -100, 0), csPoint);
  FWorldSizeMax := TgxCoordinates.CreateInitialized(self,
    VectorMake(100, 100, 100, 0), csPoint);

  // Using Events because we need to call API Function when
  // theses TgxCoordinates change.
  FWorldSizeMin.OnNotifyChange := NotifyWorldSizeChange;
  FWorldSizeMax.OnNotifyChange := NotifyWorldSizeChange;

  FThreadCount := 1;
  FGravity := TgxCoordinates3.CreateInitialized(self,
    VectorMake(0, -9.81, 0, 0), csVector);

  FNewtonWorld := NewtonCreate();  // 1.5 - NewtonCreate(nil, nil);
  FDllVersion := NewtonWorldGetVersion(); // 1.5 - NewtonWorldGetVersion(FNewtonWorld);

  // This is to prevent body out the world at startTime
  minworld := VectorMake(-1E50, -1E50, -1E50);
  maxworld := VectorMake(1E50, 1E50, 1E50);
///?  NewtonSetWorldSize(FNewtonWorld, @minworld, @maxworld);

  NewtonWorldSetUserData(FNewtonWorld, self);

  FNewtonSurfaceItem := TCollection.Create(TNGDSurfaceItem);
  FNewtonSurfacePair := TOwnedCollection.Create(self, TNGDSurfacePair);
  FNewtonJointGroup := TOwnedCollection.Create(self, TNGDJoint);

  FNGDDebugOption := TNGDDebugOption.Create(self);

  RegisterManager(self);

end;

destructor TgxNGDManager.Destroy;
begin
  // Destroy joint before body.
  FreeAndNil(FNewtonJointGroup);

  // Unregister everything
  while FNGDBehaviours.Count > 0 do
    FNGDBehaviours[0].Manager := nil;

  // Clean up everything
  FreeAndNil(FNGDBehaviours);
  FreeAndNil(FWorldSizeMin);
  FreeAndNil(FWorldSizeMax);
  FreeAndNil(FGravity);
  FreeAndNil(FNewtonSurfaceItem);
  FreeAndNil(FNewtonSurfacePair);
  FreeAndNil(FNGDDebugOption);

  NewtonDestroyAllBodies(FNewtonWorld);
  NewtonMaterialDestroyAllGroupID(FNewtonWorld);
  NewtonDestroy(FNewtonWorld);
  FNewtonWorld := nil;

  DeregisterManager(self);
  inherited;
end;

procedure TgxNGDManager.Loaded;
begin
  inherited;
  NotifyWorldSizeChange(self);
  RebuildAllJoint(self);
end;

function TgxNGDManager.GetBodyCount: Integer;
begin
  if (csDesigning in ComponentState) then
    Result := FNGDBehaviours.Count
  else
    Result := NewtonWorldGetBodyCount(FNewtonWorld);
end;

function TgxNGDManager.GetConstraintCount: Integer;
begin
  if (csDesigning in ComponentState) then
    Result := FNewtonJointGroup.Count
  else
    // Constraint is the number of joint
    Result := NewtonWorldGetConstraintCount(FNewtonWorld);
end;

procedure TgxNGDManager.NotifyChange(Sender: TObject);
var
  I: Integer;
begin
  // This event is raise
  // when debugOptions properties are edited,
  // when a behavior is initialized/finalize,
  // when joints are rebuilded, (runtime only)
  // when visible and visibleAtRuntime are edited (designTime only),
  // in manager.step, and in SetGLLines.

  // Here the manager call render method for bodies and joints in its lists

  if not Assigned(FGLLines) then
    exit;
  FGLLines.Nodes.Clear;

  if not Visible then
    exit;
  if not(csDesigning in ComponentState) then
    if not VisibleAtRunTime then
      exit;

  for I := 0 to FNGDBehaviours.Count - 1 do
    FNGDBehaviours[I].Render;

  if mdShowJoint in FNGDDebugOption.NGDManagerDebugs then
    for I := 0 to NewtonJoint.Count - 1 do //
  (NewtonJoint.Items[I] as TNGDJoint)
      .Render;

end;

procedure TgxNGDManager.SetFrictionModel(const Value: TNGDFrictionModels);
begin
  FFrictionModel := Value;
  if not(csDesigning in ComponentState) then
///&    NewtonSetFrictionModel(FNewtonWorld, Ord(FFrictionModel));
end;

procedure TgxNGDManager.SetLines(const Value: TgxLines);
begin
  if Assigned(FGLLines) then
    FGLLines.Nodes.Clear;

  FGLLines := Value;

  if Assigned(FGLLines) then
  begin
    FGLLines.SplineMode := lsmSegments;
    FGLLines.NodesAspect := lnaInvisible;
    FGLLines.Options := [loUseNodeColorForLines];
    FGLLines.Pickable := False;
    NotifyChange(self);
  end;
end;

procedure TgxNGDManager.SetMinimumFrameRate(const Value: Integer);
begin
  if (Value >= 60) and (Value <= 1000) then
    FMinimumFrameRate := Value;
  if not(csDesigning in ComponentState) then
///?    NewtonSetMinimumFrameRate(FNewtonWorld, FMinimumFrameRate);
end;

procedure TgxNGDManager.SetSolverModel(const Value: TNGDSolverModels);
begin
  FSolverModel := Value;
  if not(csDesigning in ComponentState) then
///?    NewtonSetSolverModel(FNewtonWorld, Ord(FSolverModel));
end;

procedure TgxNGDManager.SetThreadCount(const Value: Integer);
begin
  if Value > 0 then
    FThreadCount := Value;
  NewtonSetThreadsCount(FNewtonWorld, FThreadCount);
  FThreadCount := NewtonGetThreadsCount(FNewtonWorld);
end;

procedure TgxNGDManager.SetVisible(const Value: Boolean);
begin
  FVisible := Value;
  if (csDesigning in ComponentState) then
    NotifyChange(self);
end;

procedure TgxNGDManager.SetVisibleAtRunTime(const Value: Boolean);
begin
  FVisibleAtRunTime := Value;
  if (csDesigning in ComponentState) then
    NotifyChange(self);
end;

procedure TgxNGDManager.NotifyWorldSizeChange(Sender: TObject);
begin
  if not(csDesigning in ComponentState) then
///?    NewtonSetWorldSize(FNewtonWorld, @FWorldSizeMin.AsVector, @FWorldSizeMax.AsVector);
end;

procedure TgxNGDManager.RebuildAllJoint(Sender: TObject);

  procedure BuildBallAndSocket(Joint: TNGDJoint);
  begin
    with Joint do
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        FNewtonJoint := NewtonConstraintCreateBall(FNewtonWorld,
          @(FBallAndSocketOptions.FPivotPoint.AsVector),
          GetBodyFromGXSceneObject(FChildObject),
          GetBodyFromGXSceneObject(FParentObject));
        NewtonJointSetCollisionState(FNewtonJoint, Ord(FCollisionState));
        NewtonJointSetStiffness(FNewtonJoint, FStiffness);
      end;
  end;

  procedure BuildHinge(Joint: TNGDJoint);
  begin
    with Joint do
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        FNewtonJoint := NewtonConstraintCreateHinge(FNewtonWorld,
          @(FHingeOptions.FPivotPoint.AsVector),
          @(FHingeOptions.FPinDirection.AsVector),
          GetBodyFromGXSceneObject(FChildObject),
          GetBodyFromGXSceneObject(FParentObject));
        NewtonJointSetCollisionState(FNewtonJoint, Ord(FCollisionState));
        NewtonJointSetStiffness(FNewtonJoint, FStiffness);
      end;
  end;

  procedure BuildSlider(Joint: TNGDJoint);
  begin
    with Joint do
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        FNewtonJoint := NewtonConstraintCreateSlider(FNewtonWorld,
          @(FSliderOptions.FPivotPoint.AsVector),
          @(FSliderOptions.FPinDirection.AsVector),
          GetBodyFromGXSceneObject(FChildObject),
          GetBodyFromGXSceneObject(FParentObject));
        NewtonJointSetCollisionState(FNewtonJoint, Ord(FCollisionState));
        NewtonJointSetStiffness(FNewtonJoint, FStiffness);
      end;
  end;

  procedure BuildCorkscrew(Joint: TNGDJoint);
  begin
    with Joint do
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        FNewtonJoint := NewtonConstraintCreateCorkscrew(FNewtonWorld,
          @(FCorkscrewOptions.FPivotPoint.AsVector),
          @(FCorkscrewOptions.FPinDirection.AsVector),
          GetBodyFromGXSceneObject(FChildObject),
          GetBodyFromGXSceneObject(FParentObject));
        NewtonJointSetCollisionState(FNewtonJoint, Ord(FCollisionState));
        NewtonJointSetStiffness(FNewtonJoint, FStiffness);
      end;
  end;

  procedure BuildUniversal(Joint: TNGDJoint);
  begin
    with Joint do
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        FNewtonJoint := NewtonConstraintCreateUniversal(FNewtonWorld,
          @(FUniversalOptions.FPivotPoint.AsVector),
          @(FUniversalOptions.FPinDirection.AsVector),
          @(FUniversalOptions.FPinDirection2.AsVector),
          GetBodyFromGXSceneObject(FChildObject),
          GetBodyFromGXSceneObject(FParentObject));
        NewtonJointSetCollisionState(FNewtonJoint, Ord(FCollisionState));
        NewtonJointSetStiffness(FNewtonJoint, FStiffness);
      end;
  end;

  procedure BuildCustomBallAndSocket(Joint: TNGDJoint);
  var
    pinAndPivot: TMatrix;
  begin
    with Joint do
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        pinAndPivot := IdentityHmgMatrix;
        pinAndPivot.W := FCustomBallAndSocketOptions.FPivotPoint.AsVector;
        FNewtonUserJoint := CreateCustomBallAndSocket(@pinAndPivot,
          GetBodyFromGXSceneObject(FChildObject),
          GetBodyFromGXSceneObject(FParentObject));
        BallAndSocketSetConeAngle(FNewtonUserJoint,
          DegToRad(FCustomBallAndSocketOptions.FConeAngle));
        BallAndSocketSetTwistAngle(FNewtonUserJoint,
          DegToRad(FCustomBallAndSocketOptions.FMinTwistAngle),
          DegToRad(FCustomBallAndSocketOptions.FMaxTwistAngle));
        CustomSetBodiesCollisionState(FNewtonUserJoint, Ord(FCollisionState));
        NewtonJointSetStiffness(CustomGetNewtonJoint(FNewtonUserJoint),
          FStiffness);
      end;
  end;

  procedure BuildCustomHinge(Joint: TNGDJoint);
  var
    pinAndPivot: TMatrix;
    bso: TgxBaseSceneObject;
  begin
    { Newton wait from FPinAndPivotMatrix a structure like that:
      First row: the pin direction
      Second and third rows are set to create an orthogonal matrix
      Fourth: The pivot position

      In glscene, the GLBaseSceneObjects direction is the third row,
      because the first row is the right vector (second row is up vector). }
    with Joint do
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        bso := TgxBaseSceneObject.Create(FManager);
        bso.AbsolutePosition := FCustomHingeOptions.FPivotPoint.AsVector;
        bso.AbsoluteDirection := FCustomHingeOptions.FPinDirection.AsVector;
        pinAndPivot := bso.AbsoluteMatrix;
        pinAndPivot.X := bso.AbsoluteMatrix.Z;
        pinAndPivot.Z := bso.AbsoluteMatrix.X;
        bso.Free;

        FNewtonUserJoint := CreateCustomHinge(@pinAndPivot,
          GetBodyFromGXSceneObject(FChildObject),
          GetBodyFromGXSceneObject(FParentObject));
        HingeEnableLimits(FNewtonUserJoint, 1);
        HingeSetLimits(FNewtonUserJoint,
          DegToRad(FCustomHingeOptions.FMinAngle),
          DegToRad(FCustomHingeOptions.FMaxAngle));
        CustomSetBodiesCollisionState(FNewtonUserJoint, Ord(FCollisionState));
        NewtonJointSetStiffness(CustomGetNewtonJoint(FNewtonUserJoint),
          FStiffness);
        CustomSetUserData(FNewtonUserJoint, CustomHingeOptions);
      end;
  end;

  procedure BuildCustomSlider(Joint: TNGDJoint);
  var
    pinAndPivot: TMatrix;
    bso: TgxBaseSceneObject;

  begin
    { Newton wait from FPinAndPivotMatrix a structure like that:
      First row: the pin direction
      Second and third rows are set to create an orthogonal matrix
      Fourth: The pivot position

      In glscene, the GLBaseSceneObjects direction is the third row,
      because the first row is the right vector (second row is up vector). }
    with Joint do
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin

        bso := TgxBaseSceneObject.Create(FManager);
        bso.AbsolutePosition := FCustomSliderOptions.FPivotPoint.AsVector;
        bso.AbsoluteDirection := FCustomSliderOptions.FPinDirection.AsVector;
        pinAndPivot := bso.AbsoluteMatrix;
        pinAndPivot.X := bso.AbsoluteMatrix.Z;
        pinAndPivot.Z := bso.AbsoluteMatrix.X;
        bso.Free;

        FNewtonUserJoint := CreateCustomSlider(@pinAndPivot, GetBodyFromGXSceneObject(FChildObject), GetBodyFromGXSceneObject(FParentObject));
        SliderEnableLimits(FNewtonUserJoint, 1);
        SliderSetLimits(FNewtonUserJoint, FCustomSliderOptions.FMinDistance, FCustomSliderOptions.FMaxDistance);
        NewtonJointSetStiffness(CustomGetNewtonJoint(FNewtonUserJoint),0);

        CustomSetBodiesCollisionState(FNewtonUserJoint, Ord(FCollisionState));
        CustomSetUserData(FNewtonUserJoint, CustomSliderOptions);
      end;
  end;

  procedure BuildUpVector(Joint: TNGDJoint);
  begin
    with Joint do
      if Assigned(FParentObject) then
      begin
        FNewtonJoint := NewtonConstraintCreateUpVector(FNewtonWorld,
          @FUPVectorDirection.AsVector,
          GetBodyFromGXSceneObject(FParentObject));
      end;
  end;

  procedure BuildKinematicController(Joint: TNGDJoint);
  begin
    // do nothing
  end;

  procedure BuildOneJoint(Joint: TNGDJoint);
  begin
    case Joint.FJointType of
      nj_BallAndSocket:
        begin
          Joint.DestroyNewtonData;
          BuildBallAndSocket(Joint);
        end;

      nj_Hinge:
        begin
          Joint.DestroyNewtonData;
          BuildHinge(Joint);
        end;

      nj_Slider:
        begin
          Joint.DestroyNewtonData;
          BuildSlider(Joint);
        end;

      nj_Corkscrew:
        begin
          Joint.DestroyNewtonData;
          BuildCorkscrew(Joint);
        end;

      nj_Universal:
        begin
          Joint.DestroyNewtonData;
          BuildUniversal(Joint);
        end;

      nj_CustomBallAndSocket:
        begin
          Joint.DestroyNewtonData;
          BuildCustomBallAndSocket(Joint);
        end;

      nj_CustomHinge:
        begin
          Joint.DestroyNewtonData;
          BuildCustomHinge(Joint);
        end;

      nj_CustomSlider:
        begin
          Joint.DestroyNewtonData;
          BuildCustomSlider(Joint);
        end;

      nj_UpVector:
        begin
          Joint.DestroyNewtonData;
          BuildUpVector(Joint);
        end;

      nj_KinematicController:
        begin
          // DestroyJoint(Joint);
          // BuildKinematicController(Joint);
        end;
    end;
  end;

var
  i: Integer;
begin

  if not(csDesigning in ComponentState) and not(csLoading in ComponentState)
    then
  begin
    if Sender is TgxNGDManager then
      for i := 0 to NewtonJoint.Count - 1 do
        BuildOneJoint(NewtonJoint.Items[i] as TNGDJoint);

    if (Sender is TNGDJoint) then
      BuildOneJoint((Sender as TNGDJoint));

    if Sender is TgxCoordinates then
      BuildOneJoint(((Sender as TgxCoordinates).Owner as TNGDJoint));

    NotifyChange(self);
  end;

end;

procedure TgxNGDManager.RebuildAllMaterial;

  procedure BuildMaterialPair;
  var
    I, ID0, ID1: Integer;
  begin
    for I := 0 to FNewtonSurfacePair.Count - 1 do
      with (FNewtonSurfacePair.Items[I] as TNGDSurfacePair) do
      begin
        if Assigned(NGDSurfaceItem1) and Assigned(NGDSurfaceItem2) then
        begin
          ID0 := NGDSurfaceItem1.ID;
          ID1 := NGDSurfaceItem2.ID;

///?          NewtonMaterialSetContinuousCollisionMode(FNewtonWorld, ID0, ID1, Ord(ContinuousCollisionMode));
          if Thickness then
            NewtonMaterialSetSurfaceThickness(FNewtonWorld, ID0, ID1, 1);
          NewtonMaterialSetDefaultSoftness(FNewtonWorld, ID0, ID1, Softness);
          NewtonMaterialSetDefaultElasticity(FNewtonWorld, ID0, ID1,
            Elasticity);
          NewtonMaterialSetDefaultCollidable(FNewtonWorld, ID0, ID1,
            Ord(Collidable));
          NewtonMaterialSetDefaultFriction(FNewtonWorld, ID0, ID1,
            StaticFriction, KineticFriction);

///?      NewtonMaterialSetCollisionCallback(FNewtonWorld, ID0, ID1, FNewtonSurfacePair.Items[I], @TNGDSurfacePair.NewtonAABBOverlap, @TNGDSurfacePair.NewtonContactsProcess);
        end;
      end;
  end;

var
  I: Integer;
  maxID: Integer;
begin
  maxID := 0;
  if not(csDesigning in ComponentState) then
  begin
    // Destroy newton materials
    NewtonMaterialDestroyAllGroupID(FNewtonWorld);

    // Create materialID
    for I := 0 to FNewtonSurfaceItem.Count - 1 do
      maxID := MaxInteger((FNewtonSurfaceItem.Items[I] as TNGDSurfaceItem).ID,
        maxID);
    for I := 0 to maxID - 1 do
      NewtonMaterialCreateGroupID(FNewtonWorld);

    // assign matID to bodies
    for I := 0 to FNGDBehaviours.Count - 1 do
      with FNGDBehaviours[I] do
        if Assigned(FNGDSurfaceItem) then
          NewtonBodySetMaterialGroupID(FNewtonBody, FNGDSurfaceItem.ID)
        else
          NewtonBodySetMaterialGroupID(FNewtonBody, 0);

    // Set values to newton material pair :callback userdata friction...
    BuildMaterialPair;
  end;
end;

procedure TgxNGDManager.Step(deltatime: Single);
begin
  if not(csDesigning in ComponentState) then
    NewtonUpdate(FNewtonWorld, deltatime);

  NotifyChange(self);
end;

{ TgxNGDBehaviour }

constructor TgxNGDBehaviour.Create(AOwner: TXCollection);
begin
  inherited;
  FInitialized := False;
  FOwnerBaseSceneObject := OwnerBaseSceneObject;

  FContinuousCollisionMode := False;
  FNewtonBody := nil;
  FCollision := nil;

  FNGDNewtonCollisions := nc_Primitive;

  FCollisionIteratorEvent := OnCollisionIteratorEvent;

  FTreeCollisionOptimize := True;
  FConvexCollisionTolerance := 0.01;
  FFileCollision := '';
  name := 'NGD Static';
end;

destructor TgxNGDBehaviour.Destroy;
begin
  if Assigned(FManager) then
    Manager := nil;  // This will call finalize
  inherited;
end;

procedure TgxNGDBehaviour.Finalize;
var
  i: integer;
begin
  FInitialized := False;

  if Assigned(FManager) then
  begin

    if Assigned(FManager.NewtonJoint) then
    for i := FManager.NewtonJoint.Count-1 downto 0 do
    begin
      if ((FManager.NewtonJoint.Items[i] as TNGDJoint).ParentObject = FOwnerBaseSceneObject)
      or ((FManager.NewtonJoint.Items[i] as TNGDJoint).ChildObject = FOwnerBaseSceneObject) then
      begin
        FManager.NewtonJoint.Items[i].Free;
      end;
    end;

    NewtonDestroyBody(FNewtonBody);
    FNewtonBody := nil;
    FCollision := nil;
  end;
end;

function TgxNGDBehaviour.GetBBoxCollision: PNewtonCollision;
var
  vc: array [0 .. 7] of TVector;
  I: Integer;
begin
  for I := 0 to 8 - 1 do
    vc[I] := AABBToBB(FOwnerBaseSceneObject.AxisAlignedBoundingBoxEx).BBox[I];
  Result := NewtonCreateConvexHull(FManager.FNewtonWorld, 8, @vc[0],
    SizeOf(TVector), 0.01, 0, nil);
end;

function TgxNGDBehaviour.GetBSphereCollision: PNewtonCollision;
var
  boundingSphere: TBSphere;
  collisionOffsetMatrix: TMatrix;
begin
  AABBToBSphere(FOwnerBaseSceneObject.AxisAlignedBoundingBoxEx, boundingSphere);

  collisionOffsetMatrix := IdentityHmgMatrix;
  collisionOffsetMatrix.W := VectorMake(boundingSphere.Center, 1);
///?  Result := NewtonCreateSphere(FManager.FNewtonWorld, boundingSphere.Radius, boundingSphere.Radius, boundingSphere.Radius, 0, @collisionOffsetMatrix);
end;

function TgxNGDBehaviour.GetConvexCollision: PNewtonCollision;
var
  I, J: Integer;
  vertexArray: array of TVertex;
begin
  if FOwnerBaseSceneObject is TgxBaseMesh then
  begin
    with (FOwnerBaseSceneObject as TgxBaseMesh) do
    begin

      for I := 0 to MeshObjects.Count - 1 do
        for J := 0 to MeshObjects[I].Vertices.Count - 1 do
        begin
          SetLength(vertexArray, Length(vertexArray) + 1);
          vertexArray[Length(vertexArray) - 1] := MeshObjects[I].Vertices[J];
        end;

      if Length(vertexArray) > 0 then
        Result := NewtonCreateConvexHull(FManager.FNewtonWorld,
          Length(vertexArray), @vertexArray[0], SizeOf(TVertex),
          FConvexCollisionTolerance, 0, nil)
      else
        Result := GetNullCollision;

    end;
  end
  else
    Result := GetNullCollision;
end;

function TgxNGDBehaviour.GetHeightFieldCollision: PNewtonCollision;
var
  I: Integer;
  attributeMap: array of ShortInt;
begin
  SetLength(attributeMap, Length(FHeightFieldOptions.heightArray));
  for I := 0 to Length(FHeightFieldOptions.heightArray) - 1 do
    attributeMap[I] := 0;

///?
(*
  Result := NewtonCreateHeightFieldCollision(FManager.FNewtonWorld,
      FHeightFieldOptions.width, FHeightFieldOptions.depth,
      Ord(FHeightFieldOptions.gridDiagonals),
      PUnsigned_short(FHeightFieldOptions.heightArray),
      P2Char(attributeMap), FHeightFieldOptions.widthDepthScale,
      FHeightFieldOptions.heightScale, 0);
*)
end;

function TgxNGDBehaviour.GetMeshCollision: PNewtonCollision;
var
  collisionArray: array of PNewtonCollision;
  I, J: Integer;
  vertexArray: array of TVertex;
begin
  if FOwnerBaseSceneObject is TgxBaseMesh then
  begin
    with (FOwnerBaseSceneObject as TgxBaseMesh) do
    begin

      // Iterate trough mesh of GLobject
      for I := 0 to MeshObjects.Count - 1 do
      begin
        // Iterate trough vertices of mesh
        for J := 0 to MeshObjects[I].Vertices.Count - 1 do
        begin
          SetLength(vertexArray, Length(vertexArray) + 1);
          vertexArray[Length(vertexArray) - 1] := MeshObjects[I].Vertices[J];
        end;

        if Length(vertexArray) > 3 then
        begin
          SetLength(collisionArray, Length(collisionArray) + 1);

          collisionArray[Length(collisionArray) - 1] := NewtonCreateConvexHull
            (FManager.FNewtonWorld, Length(vertexArray), @vertexArray[0],
            SizeOf(TVertex), FConvexCollisionTolerance, 0, nil);

          // Remove last collision if the newton function was not successful
          if collisionArray[Length(collisionArray) - 1] = nil then
            SetLength(collisionArray, Length(collisionArray) - 1);

        end;
        SetLength(vertexArray, 0);
      end;

      if Length(collisionArray) > 0 then
///?   Result := NewtonCreateCompoundCollision(FManager.FNewtonWorld, Length(collisionArray), TCollisionPrimitiveArray(@collisionArray[0]), 0)
      else
        Result := GetNullCollision;

    end;
  end
  else
    Result := GetNullCollision;

end;


function TgxNGDBehaviour.GetNewtonBodyMatrix: TMatrix;
begin
  if Assigned(FManager) then
    NewtonBodyGetmatrix(FNewtonBody, @FNewtonBodyMatrix);
  Result := FNewtonBodyMatrix;
end;

function TgxNGDBehaviour.GetNewtonBodyAABB: TAABB;
begin
  if Assigned(FManager) then
    NewtonBodyGetAABB(FNewtonBody, @(Result.min), @(Result.max));
end;

function TgxNGDBehaviour.GetNGDFileCollision: PNewtonCollision;
var
  MyFile: TFileStream;
begin

  if FileExists(FFileCollision) then
  begin
    MyFile := TFileStream.Create(FFileCollision, fmOpenRead);

    Result := NewtonCreateCollisionFromSerialization(FManager.FNewtonWorld,
      @TgxNGDBehaviour.NewtonDeserialize, Pointer(MyFile));

    MyFile.Free;
  end
  else
    Result := NewtonCreateNull(FManager.FNewtonWorld);

end;

function TgxNGDBehaviour.GetNullCollision: PNewtonCollision;
begin
  Result := NewtonCreateNull(FManager.FNewtonWorld);
end;

function TgxNGDBehaviour.GetPrimitiveCollision: PNewtonCollision;
var
  collisionOffsetMatrix: TMatrix; // For cone capsule and cylinder
begin
  collisionOffsetMatrix := IdentityHmgMatrix;

  if (FOwnerBaseSceneObject is TgxCube) then
  begin
    with (FOwnerBaseSceneObject as TgxCube) do
      Result := NewtonCreateBox(FManager.FNewtonWorld, CubeWidth, CubeHeight,
        CubeDepth, 0, @collisionOffsetMatrix);
  end

  else if (FOwnerBaseSceneObject is TgxSphere) then
  begin
    with (FOwnerBaseSceneObject as TgxSphere) do
///?      Result := NewtonCreateSphere(FManager.FNewtonWorld, Radius, Radius, Radius, 0, @collisionOffsetMatrix);
  end

  else if (FOwnerBaseSceneObject is TgxCone) then
  begin
    collisionOffsetMatrix := MatrixMultiply(collisionOffsetMatrix,
      CreateRotationMatrixZ(Pi / 2.0));
    with (FOwnerBaseSceneObject as TgxCone) do
      Result := NewtonCreateCone(FManager.FNewtonWorld, BottomRadius, Height,
        0, @collisionOffsetMatrix);
  end

  else if (FOwnerBaseSceneObject is TgxCapsule) then
  begin
    collisionOffsetMatrix := MatrixMultiply(collisionOffsetMatrix,
      CreateRotationMatrixY(Pi / 2.0));
    with (FOwnerBaseSceneObject as TgxCapsule) do
      // Use Cylinder shape for buoyancy
///?      Result := NewtonCreateCapsule(FManager.FNewtonWorld, Radius,  Height + 2 * Radius, 0, @collisionOffsetMatrix);
  end

  else if (FOwnerBaseSceneObject is TgxCylinder) then
  begin
    collisionOffsetMatrix := MatrixMultiply(collisionOffsetMatrix,
      CreateRotationMatrixZ(Pi / 2.0));
    with (FOwnerBaseSceneObject as TgxCylinder) do
//?      Result := NewtonCreateCylinder(FManager.FNewtonWorld, BottomRadius, Height, 0, @collisionOffsetMatrix);
  end
  else
    Result := GetNullCollision;
end;

function TgxNGDBehaviour.GetTreeCollision: PNewtonCollision;
var
  meshIndex, triangleIndex: Integer;
  triangleList: TAffineVectorList;
  v: array [0 .. 2] of TAffineVector;
begin

  if FOwnerBaseSceneObject is TgxBaseMesh then
  begin
    with (FOwnerBaseSceneObject as TgxBaseMesh) do
    begin
      Result := NewtonCreateTreeCollision(FManager.FNewtonWorld, 0);
      NewtonTreeCollisionBeginBuild(Result);

      for meshIndex := 0 to MeshObjects.Count - 1 do
      begin
        triangleList := MeshObjects[meshIndex].ExtractTriangles;
        for triangleIndex := 0 to triangleList.Count - 1 do
        begin
          if triangleIndex mod 3 = 0 then
          begin
            v[0] := triangleList.Items[triangleIndex];
            // ScaleVector(v[0], FOwnerBaseSceneObject.Scale.X);
            v[1] := triangleList.Items[triangleIndex + 1];
            // ScaleVector(v[1], FOwnerBaseSceneObject.Scale.Y);
            v[2] := triangleList.Items[triangleIndex + 2];
            // ScaleVector(v[2], FOwnerBaseSceneObject.Scale.Z);
            NewtonTreeCollisionAddFace(Result, 3, @(v), SizeOf(TAffineVector),
              1);
          end;
        end;
        triangleList.Free;
      end;
      NewtonTreeCollisionEndBuild(Result, Ord(FTreeCollisionOptimize));
    end;
  end
  else
    Result := GetNullCollision;

end;

procedure TgxNGDBehaviour.Initialize;
begin
  FInitialized := True;

  if Assigned(FManager) then
  begin
    // Create NewtonBody with null collision
    FCollision := NewtonCreateNull(FManager.FNewtonWorld);
    FNewtonBodyMatrix := FOwnerBaseSceneObject.AbsoluteMatrix;
    FNewtonBody := NewtonCreateDynamicBody(FManager.FNewtonWorld, FCollision, @FNewtonBodyMatrix);

    // Release NewtonCollision
///?    NewtonReleaseCollision(FManager.FNewtonWorld, FCollision);

    // Set Link between glscene and newton
    NewtonBodySetUserdata(FNewtonBody, self);

    // Set position and orientation
    SetNewtonBodyMatrix(FOwnerBaseSceneObject.AbsoluteMatrix);

    // Set Collision
    UpdCollision;

  end;
end;

procedure TgxNGDBehaviour.Loaded;
var
  mng: TComponent;
begin
  inherited;
  if FManagerName <> '' then
  begin
    mng := FindManager(TgxNGDManager, FManagerName);
    if Assigned(mng) then
      Manager := TgxNGDManager(mng);
    FManagerName := '';
  end;

  if Assigned(FManager) then
  begin
    SetContinuousCollisionMode(FContinuousCollisionMode);
  end;
end;

class procedure TgxNGDBehaviour.NewtonCollisionIterator
  (const userData: Pointer; vertexCount: Integer; const faceArray: PNGDFloat;
  faceId: Integer)cdecl;
begin
  TgxNGDBehaviour(userData).FCollisionIteratorEvent(userData, vertexCount,
    faceArray, faceId);
end;

// Serializes are called by NGDBehaviour to save and load collision in file
// It's better to save/load big collisions [over 50000 polygones] to reduce
// loading time
class procedure TgxNGDBehaviour.NewtonDeserialize(serializeHandle,
  buffer: Pointer; size: Cardinal)cdecl;
begin
  TFileStream(serializeHandle).read(buffer^, size);
end;

class procedure TgxNGDBehaviour.NewtonSerialize(serializeHandle: Pointer;
  const buffer: Pointer; size: Cardinal)cdecl;
begin
  TFileStream(serializeHandle).write(buffer^, size);
end;

procedure TgxNGDBehaviour.OnCollisionIteratorEvent(const userData: Pointer;
  vertexCount: Integer; const cfaceArray: PNGDFloat; faceId: Integer);
var
  I: Integer;
  v0, v1: array [0 .. 2] of Single;
  vA: array of Single;
begin
  // This algorithme draw Collision Shape for Debuggin.
  // Taken to Sascha Willems in SDLNewton-Demo at
  // http://www.saschawillems.de/?page_id=82

  // Leave if there is no or to much vertex
  if (vertexCount = 0) then
    exit;

  SetLength(vA, vertexCount * 3);
  Move(cfaceArray^, vA[0], vertexCount * 3 * SizeOf(Single));
  v0[0] := vA[(vertexCount - 1) * 3];
  v0[1] := vA[(vertexCount - 1) * 3 + 1];
  v0[2] := vA[(vertexCount - 1) * 3 + 2];
  for I := 0 to vertexCount - 1 do
  begin
    v1[0] := vA[I * 3];
    v1[1] := vA[I * 3 + 1];
    v1[2] := vA[I * 3 + 2];
    FManager.AddNode(v0[0], v0[1], v0[2]);
    FManager.AddNode(v1[0], v1[1], v1[2]);
    v0 := v1;
  end;
end;

procedure TgxNGDBehaviour.Reinitialize;
begin
  if Initialized then
  begin
    // Set Appropriate NewtonCollision
    UpdCollision();
    // Set position and orientation
    SetNewtonBodyMatrix(FOwnerBaseSceneObject.AbsoluteMatrix);
  end;
  Loaded;
end;

procedure TgxNGDBehaviour.Render;
var
  M: TMatrix;
begin
  // Rebuild collision in design time
  if (csDesigning in FOwnerBaseSceneObject.ComponentState) then
    Reinitialize;

  if self is TgxNGDDynamic then
    FManager.FCurrentColor := FManager.DebugOption.GeomColorDyn
  else
    FManager.FCurrentColor := FManager.DebugOption.GeomColorStat;

  M := FOwnerBaseSceneObject.AbsoluteMatrix;

  if mdShowGeometry in FManager.DebugOption.NGDManagerDebugs then
    NewtonCollisionForEachPolygonDo(FCollision, @M,
      @TgxNGDBehaviour.NewtonCollisionIterator, self);
end;

// In this procedure, we assign collision to body
// [Because when initialised, the collision for body is type NULL]
procedure TgxNGDBehaviour.UpdCollision;
var
  collisionInfoRecord: TNewtonCollisionInfoRecord;
begin

  case FNGDNewtonCollisions of
    nc_Primitive:
      FCollision := GetPrimitiveCollision;
    nc_Convex:
      FCollision := GetConvexCollision;
    nc_BBox:
      FCollision := GetBBoxCollision;
    nc_BSphere:
      FCollision := GetBSphereCollision;
    nc_Tree:
      FCollision := GetTreeCollision;
    nc_Mesh:
      FCollision := GetMeshCollision;
    nc_Null:
      FCollision := GetNullCollision;
    nc_HeightField:
      FCollision := GetHeightFieldCollision;
    nc_NGDFile:
      FCollision := GetNGDFileCollision;
  end;

  if Assigned(FCollision) then
  begin
    NewtonBodySetCollision(FNewtonBody, FCollision);

    // The API Ask for releasing Collision to avoid memory leak
    NewtonCollisionGetInfo(FCollision, @collisionInfoRecord);
///?    if collisionInfoRecord.m_referenceCount > 2 then
///?     NewtonReleaseCollision(FManager.FNewtonWorld, FCollision);
  end;

end;

procedure TgxNGDBehaviour.SetContinuousCollisionMode(const Value: Boolean);
begin
  // for continue collision to be active the continue collision mode must on
  // the material pair of the colliding bodies as well as on at
  // least one of the two colliding bodies.
  // see NewtonBodySetContinuousCollisionMode
  // see NewtonMaterialSetContinuousCollisionMode
  FContinuousCollisionMode := Value;
  if not(csDesigning in FOwnerBaseSceneObject.ComponentState) then
    if Assigned(FManager) then
      NewtonBodySetContinuousCollisionMode(FNewtonBody, Ord(Value));
end;

procedure TgxNGDBehaviour.SetHeightFieldOptions(const Value: TgxHeightField);
begin
  FHeightFieldOptions := Value;
  Reinitialize;
end;

procedure TgxNGDBehaviour.SetManager(Value: TgxNGDManager);
begin
  if FManager <> Value then
  begin
    if Assigned(FManager) then
    begin
      if Initialized then
        Finalize;
      FManager.FNGDBehaviours.Remove(self);
      // FManager.NotifyChange(self);
    end;
    FManager := Value;
    if Assigned(FManager) then
    begin
      Initialize;
      FManager.FNGDBehaviours.Add(self);
      FManager.NotifyChange(self);
    end;
  end;
end;

procedure TgxNGDBehaviour.SetNewtonBodyMatrix(const Value: TMatrix);
begin
  FNewtonBodyMatrix := Value;
  if Assigned(FManager) then
    NewtonBodySetmatrix(FNewtonBody, @FNewtonBodyMatrix);
end;

procedure TgxNGDBehaviour.SetNGDNewtonCollisions
  (const Value: TNGDNewtonCollisions);
begin
  FNGDNewtonCollisions := Value;
  if Assigned(FManager) then
    UpdCollision;
end;

procedure TgxNGDBehaviour.SetNGDSurfaceItem(const Value: TNGDSurfaceItem);
begin
  FNGDSurfaceItem := Value;
  FManager.RebuildAllMaterial;
end;

function TgxNGDBehaviour.StoredTolerance: Boolean;
begin
  Result := not SameValue(FConvexCollisionTolerance, 0.01, epsilon);
end;

class function TgxNGDBehaviour.UniqueItem: Boolean;
begin
  Result := True;
end;

procedure TgxNGDBehaviour.ReadFromFiler(reader: TReader);
var
  version: Integer;
begin
  inherited;
  with reader do
  begin
    version := ReadInteger; // read data version
    Assert(version <= 1); // Archive version

    FManagerName := ReadString;
    FContinuousCollisionMode := ReadBoolean;
    read(FNGDNewtonCollisions, SizeOf(TNGDNewtonCollisions));
    FTreeCollisionOptimize := ReadBoolean;
    if version <= 0 then
      FConvexCollisionTolerance := ReadSingle
    else
      FConvexCollisionTolerance := ReadFloat;
    FFileCollision := ReadString;
  end;
end;

procedure TgxNGDBehaviour.WriteToFiler(writer: TWriter);
begin
  inherited;
  with writer do
  begin
    WriteInteger(1); // Archive version
    if Assigned(FManager) then
      WriteString(FManager.GetNamePath)
    else
      WriteString('');
    WriteBoolean(FContinuousCollisionMode);
    write(FNGDNewtonCollisions, SizeOf(TNGDNewtonCollisions));
    WriteBoolean(FTreeCollisionOptimize);
    WriteFloat(FConvexCollisionTolerance);
    WriteString(FFileCollision);
  end;
end;

procedure TgxNGDBehaviour.Serialize(filename: string);
var
  MyFile: TFileStream;
begin
  MyFile := TFileStream.Create(filename, fmCreate or fmOpenReadWrite);

  NewtonCollisionSerialize(FManager.FNewtonWorld, FCollision,
    @TgxNGDBehaviour.NewtonSerialize, Pointer(MyFile));

  MyFile.Free;
end;

procedure TgxNGDBehaviour.DeSerialize(filename: string);
var
  MyFile: TFileStream;
  collisionInfoRecord: TNewtonCollisionInfoRecord;
begin
  MyFile := TFileStream.Create(filename, fmOpenRead);

  FCollision := NewtonCreateCollisionFromSerialization(FManager.FNewtonWorld,
    @TgxNGDBehaviour.NewtonDeserialize, Pointer(MyFile));

  // SetCollision;
  NewtonBodySetCollision(FNewtonBody, FCollision);

  // Release collision
  NewtonCollisionGetInfo(FCollision, @collisionInfoRecord);
///?  if collisionInfoRecord.m_referenceCount > 2 then
///?   NewtonReleaseCollision(FManager.FNewtonWorld, FCollision);

  MyFile.Free;
end;

//-------------------------------------
// TgxNGDDynamic
//-------------------------------------

procedure TgxNGDDynamic.AddImpulse(const veloc, pointposit: TVector);
begin
  if Assigned(FNewtonBody) then
///?    NewtonBodyAddImpulse(FNewtonBody, @veloc, @pointposit);
end;

constructor TgxNGDDynamic.Create(AOwner: TXCollection);
begin
  inherited;
  FAutoSleep := True;
  FLinearDamping := 0.1;
  FAngularDamping := TgxCoordinates.CreateInitialized(self,
    VectorMake(0.1, 0.1, 0.1, 0), csPoint);
  FAngularDamping.OnNotifyChange := NotifyAngularDampingChange;
  FDensity := 1;
  FVolume := 1;
  FForce := TgxCoordinates.CreateInitialized(self, NullHmgVector, csVector);
  FTorque := TgxCoordinates.CreateInitialized(self, NullHmgVector, csVector);
  FCenterOfMass := TgxCoordinates.CreateInitialized(self, NullHmgVector,
    csPoint);
  FCenterOfMass.OnNotifyChange := NotifyCenterOfMassChange;
  FAABBmin := TgxCoordinates.CreateInitialized(self, NullHmgVector, csPoint);
  FAABBmax := TgxCoordinates.CreateInitialized(self, NullHmgVector, csPoint);
  FAppliedOmega := TgxCoordinates.CreateInitialized(self, NullHmgVector,
    csVector);
  FAppliedVelocity := TgxCoordinates.CreateInitialized(self, NullHmgVector,
    csVector);
  FAppliedForce := TgxCoordinates.CreateInitialized(self, NullHmgVector,
    csVector);
  FAppliedTorque := TgxCoordinates.CreateInitialized(self, NullHmgVector,
    csVector);
  FUseGravity := True;
  FNullCollisionVolume := 0;

  FApplyForceAndTorqueEvent := OnApplyForceAndTorqueEvent;
  FSetTransformEvent := OnSetTransformEvent;
  name := 'NGD Dynamic'
end;

destructor TgxNGDDynamic.Destroy;
begin
  // Clean up everything
  FAngularDamping.Free;
  FForce.Free;
  FTorque.Free;
  FCenterOfMass.Free;
  FAABBmin.Free;
  FAABBmax.Free;
  FAppliedForce.Free;
  FAppliedTorque.Free;
  FAppliedVelocity.Free;
  FAppliedOmega.Free;
  inherited;
end;

procedure TgxNGDDynamic.Finalize;
begin
  if not(csDesigning in FOwnerBaseSceneObject.ComponentState) then
    if Assigned(FManager) then
    begin
      // Removing Callback
      NewtonBodySetForceAndTorqueCallback(FNewtonBody, nil);
      NewtonBodySetTransformCallback(FNewtonBody, nil);
    end;
  inherited;
end;

class function TgxNGDDynamic.FriendlyName: string;
begin
  Result := 'NGD Dynamic';
end;


procedure TgxNGDDynamic.Initialize;
begin
  inherited;
  if not(csDesigning in FOwnerBaseSceneObject.ComponentState) then
    if Assigned(FManager) then
    begin
      // Set Density, Mass and inertie matrix
      SetDensity(FDensity);

      // Set Callback
      NewtonBodySetForceAndTorqueCallback(FNewtonBody,
        @TgxNGDDynamic.NewtonApplyForceAndTorque);
      NewtonBodySetTransformCallback(FNewtonBody,
        @TgxNGDDynamic.NewtonSetTransform);
    end;
end;

procedure TgxNGDDynamic.Render;

  procedure DrawAABB(min, max: TgxCoordinates3);
  begin

    {
      //    H________G
      //   /.       /|
      //  / .      / |
      // D__._____C  |
      // |  .     |  |
      // | E.-----|--F
      // | .      | /
      // |.       |/
      // A________B
      }
    // Back
    FManager.AddNode(min.X, min.Y, min.Z); // E
    FManager.AddNode(max.X, min.Y, min.Z); // F

    FManager.AddNode(max.X, min.Y, min.Z); // F
    FManager.AddNode(max.X, max.Y, min.Z); // G

    FManager.AddNode(max.X, max.Y, min.Z); // G
    FManager.AddNode(min.X, max.Y, min.Z); // H

    FManager.AddNode(min.X, max.Y, min.Z); // H
    FManager.AddNode(min.X, min.Y, min.Z); // E

    // Front
    FManager.AddNode(min.X, min.Y, max.Z); // A
    FManager.AddNode(max.X, min.Y, max.Z); // B

    FManager.AddNode(max.X, min.Y, max.Z); // B
    FManager.AddNode(max.X, max.Y, max.Z); // C

    FManager.AddNode(max.X, max.Y, max.Z); // C
    FManager.AddNode(min.X, max.Y, max.Z); // D

    FManager.AddNode(min.X, max.Y, max.Z); // D
    FManager.AddNode(min.X, min.Y, max.Z); // A

    // Edges
    FManager.AddNode(min.X, min.Y, max.Z); // A
    FManager.AddNode(min.X, min.Y, min.Z); // E

    FManager.AddNode(max.X, min.Y, max.Z); // B
    FManager.AddNode(max.X, min.Y, min.Z); // F

    FManager.AddNode(max.X, max.Y, max.Z); // C
    FManager.AddNode(max.X, max.Y, min.Z); // G

    FManager.AddNode(min.X, max.Y, max.Z); // D
    FManager.AddNode(min.X, max.Y, min.Z); // H
  end;

  procedure DrawContact;
  var
    cnt: PNewtonJoint;
    thisContact: PNewtonJoint;
    material: PNewtonMaterial;
    pos, nor: TVector;
  begin
    FManager.FCurrentColor := FManager.DebugOption.ContactColor;
    cnt := NewtonBodyGetFirstContactJoint(FNewtonBody);
    while cnt <> nil do
    begin
      thisContact := NewtonContactJointGetFirstContact(cnt);
      while thisContact <> nil do
      begin
        material := NewtonContactGetMaterial(thisContact);
        NewtonMaterialGetContactPositionAndNormal(material, FNewtonBody, @pos, @nor);

        FManager.AddNode(pos);
        nor := VectorAdd(pos, nor);
        FManager.AddNode(nor);

        thisContact := NewtonContactJointGetNextContact(cnt, thisContact);
      end;
      cnt := NewtonBodyGetNextContactJoint(FNewtonBody, cnt);
    end;
  end;

  function GetAbsCom(): TVector;
  var
    M: TMatrix;
  begin
    NewtonBodyGetCentreOfMass(FNewtonBody, @Result);
    M := IdentityHmgMatrix;
    M.W := Result;
    M.W.W := 1;
    M := MatrixMultiply(M, FOwnerBaseSceneObject.AbsoluteMatrix);
    Result := M.W;
  end;

  procedure DrawForce;
  var
    pos: TVector;
    nor: TVector;
  begin
    pos := GetAbsCom;

    if mdShowForce in FManager.DebugOption.NGDManagerDebugs then
    begin
      FManager.FCurrentColor := FManager.DebugOption.ForceColor;
      nor := VectorAdd(pos, FForce.AsVector);
      FManager.AddNode(pos);
      FManager.AddNode(nor);
    end;

    if mdShowAppliedForce in FManager.DebugOption.NGDManagerDebugs then
    begin
      FManager.FCurrentColor := FManager.DebugOption.AppliedForceColor;
      nor := VectorAdd(pos, FAppliedForce.AsVector);
      FManager.AddNode(pos);
      FManager.AddNode(nor);

    end;

    if mdShowAppliedVelocity in FManager.DebugOption.NGDManagerDebugs then
    begin
      FManager.FCurrentColor := FManager.DebugOption.AppliedVelocityColor;
      nor := VectorAdd(pos, FAppliedVelocity.AsVector);
      FManager.AddNode(pos);
      FManager.AddNode(nor);
    end;

  end;

  procedure DrawCoM;
  var
    com: TVector;
    size: Single;
  begin
    FManager.FCurrentColor := FManager.DebugOption.CenterOfMassColor;
    size := FManager.DebugOption.DotAxisSize;
    com := GetAbsCom;
    FManager.AddNode(VectorAdd(com, VectorMake(0, 0, size)));
    FManager.AddNode(VectorAdd(com, VectorMake(0, 0, -size)));
    FManager.AddNode(VectorAdd(com, VectorMake(0, size, 0)));
    FManager.AddNode(VectorAdd(com, VectorMake(0, -size, 0)));
    FManager.AddNode(VectorAdd(com, VectorMake(size, 0, 0)));
    FManager.AddNode(VectorAdd(com, VectorMake(-size, 0, 0)));
  end;

begin
  inherited;

  // Move/Rotate NewtonObject if matrix are not equal in design time.
  if (csDesigning in FOwnerBaseSceneObject.ComponentState) then
    if not MatrixEquals(NewtonBodyMatrix, FOwnerBaseSceneObject.AbsoluteMatrix)
      then
      SetNewtonBodyMatrix(FOwnerBaseSceneObject.AbsoluteMatrix);

  NewtonBodyGetAABB(FNewtonBody, @(FAABBmin.AsVector), @(FAABBmax.AsVector));

  if NewtonBodyGetSleepState(FNewtonBody) = 1 then
    FManager.FCurrentColor := FManager.DebugOption.AABBColorSleep
  else
    FManager.FCurrentColor := FManager.DebugOption.AABBColor;

  if mdShowAABB in FManager.DebugOption.NGDManagerDebugs then
    DrawAABB(FAABBmin, FAABBmax);

  if mdShowContact in FManager.DebugOption.NGDManagerDebugs then
    DrawContact;

  DrawForce; // Draw Force, AppliedForce and AppliedVelocity

  if mdShowCenterOfMass in FManager.DebugOption.NGDManagerDebugs then
    DrawCoM;
end;

procedure TgxNGDDynamic.SetAutoSleep(const Value: Boolean);
begin
  FAutoSleep := Value;
  if not(csDesigning in FOwnerBaseSceneObject.ComponentState) then
    if Assigned(FManager) then
      NewtonBodySetAutoSleep(FNewtonBody, Ord(FAutoSleep));
end;

procedure TgxNGDDynamic.SetDensity(const Value: Single);
var
  inertia: TVector;
  origin: TVector;
begin
  if Assigned(FManager) then
    if Value >= 0 then
    begin
      FDensity := Value;

      FVolume := NewtonConvexCollisionCalculateVolume(FCollision);
      NewtonConvexCollisionCalculateInertialMatrix(FCollision, @inertia,
        @origin);

      if IsZero(FVolume, epsilon) then
      begin
        FVolume := FNullCollisionVolume;
        inertia := VectorMake(FNullCollisionVolume, FNullCollisionVolume,
          FNullCollisionVolume, 0);
      end;

      FMass := FVolume * FDensity;

      if not(csDesigning in FOwnerBaseSceneObject.ComponentState) then
        NewtonBodySetMassMatrix(FNewtonBody, FMass, FMass * inertia.X,
          FMass * inertia.Y, FMass * inertia.Z);

      FCenterOfMass.AsVector := origin;
    end;
end;

procedure TgxNGDDynamic.SetLinearDamping(const Value: Single);
begin
  if (Value >= 0) and (Value <= 1) then
    FLinearDamping := Value;
  if not(csDesigning in FOwnerBaseSceneObject.ComponentState) then
    if Assigned(FManager) then
      NewtonBodySetLinearDamping(FNewtonBody, FLinearDamping);
end;

function TgxNGDDynamic.GetOmega: TVector;
begin
  NewtonBodyGetOmega(FNewtonBody, @Result);
end;

procedure TgxNGDDynamic.SetOmega(const Omega: TVector);
begin
  NewtonBodySetOmega(FNewtonBody, @Omega);
end;

function TgxNGDDynamic.GetVelocity: TVector;
begin
  NewtonBodyGetVelocity(FNewtonBody, @Result);
end;

procedure TgxNGDDynamic.SetVelocity(const Velocity: TVector);
begin
  NewtonBodySetVelocity(FNewtonBody, @Velocity);
end;

function TgxNGDDynamic.StoredDensity: Boolean;
begin
  Result := not SameValue(FDensity, 1, epsilon);
end;

function TgxNGDDynamic.StoredLinearDamping: Boolean;
begin
  Result := not SameValue(FLinearDamping, 0.1, epsilon);
end;

function TgxNGDDynamic.StoredNullCollisionVolume: Boolean;
begin
  Result := not SameValue(FNullCollisionVolume, 0, epsilon);
end;

// WriteToFiler
//
procedure TgxNGDDynamic.WriteToFiler(writer: TWriter);
begin
  inherited;
  with writer do
  begin
    WriteInteger(1); // Archive version
    WriteBoolean(FAutoSleep);
    WriteFloat(FLinearDamping);
    WriteFloat(FDensity);
    WriteBoolean(FUseGravity);
    WriteFloat(FNullCollisionVolume);
  end;
  FForce.WriteToFiler(writer);
  FTorque.WriteToFiler(writer);
  FCenterOfMass.WriteToFiler(writer);
  FAngularDamping.WriteToFiler(writer);
end;

// ReadFromFiler
//
procedure TgxNGDDynamic.ReadFromFiler(reader: TReader);
var
  version: Integer;
begin
  inherited;
  with reader do
  begin
    version := ReadInteger; // read data version
    Assert(version <= 1); // Archive version

    FAutoSleep := ReadBoolean;
    if version <= 0 then
      FLinearDamping := ReadSingle
    else
      FLinearDamping := ReadFloat;
    if version <= 0 then
      FDensity := ReadSingle
    else
      FDensity := ReadFloat;

    // if Version >= 1 then
    FUseGravity := ReadBoolean;

    if version <= 0 then
      FNullCollisionVolume := ReadSingle
    else
      FNullCollisionVolume := ReadFloat;

  end;
  FForce.ReadFromFiler(reader);
  FTorque.ReadFromFiler(reader);
  FCenterOfMass.ReadFromFiler(reader);
  FAngularDamping.ReadFromFiler(reader);
end;

procedure TgxNGDDynamic.Loaded;
begin
  inherited;
  if Assigned(FManager) then
  begin
    SetAutoSleep(FAutoSleep);
    SetLinearDamping(FLinearDamping);
    SetDensity(FDensity);
    NotifyCenterOfMassChange(self);
    NotifyAngularDampingChange(self);
  end;
end;

class procedure TgxNGDDynamic.NewtonApplyForceAndTorque
  (const body: PNewtonBody; timestep: NGDFloat; threadIndex: Integer); cdecl;
begin
  TgxNGDDynamic(NewtonBodyGetUserData(body)).FApplyForceAndTorqueEvent(body,
    timestep, threadIndex);
end;

class procedure TgxNGDDynamic.NewtonSetTransform(const body: PNewtonBody;
  const matrix: PNGDFloat; threadIndex: Integer); cdecl;
begin
  TgxNGDDynamic(NewtonBodyGetUserData(body)).FSetTransformEvent(body, matrix,
    threadIndex);
end;

procedure TgxNGDDynamic.NotifyAngularDampingChange(Sender: TObject);
begin
  FAngularDamping.OnNotifyChange := nil;
  if (FAngularDamping.X >= 0) and (FAngularDamping.X <= 1) and
    (FAngularDamping.Y >= 0) and (FAngularDamping.Y <= 1) and
    (FAngularDamping.Z >= 0) and (FAngularDamping.Z <= 1) then
    if Assigned(FManager) then
      NewtonBodySetAngularDamping(FNewtonBody, @(FAngularDamping.AsVector));
  FAngularDamping.OnNotifyChange := NotifyAngularDampingChange;
end;

procedure TgxNGDDynamic.NotifyCenterOfMassChange(Sender: TObject);
begin
  FCenterOfMass.OnNotifyChange := nil;
  if Assigned(FManager) then
    NewtonBodySetCentreOfMass(FNewtonBody, @(FCenterOfMass.AsVector));
  FCenterOfMass.OnNotifyChange := NotifyCenterOfMassChange;
end;

procedure TgxNGDDynamic.OnApplyForceAndTorqueEvent(const cbody: PNewtonBody;
  timestep: NGDFloat; threadIndex: Integer);
var
  worldGravity: TVector;
begin

  // Read Only: We get the force and torque resulting from every interaction on this body
  NewtonBodyGetForce(cbody, @(FAppliedForce.AsVector));
  NewtonBodyGetTorque(cbody, @(FAppliedTorque.AsVector));

  NewtonBodyGetVelocity(cbody, @(FAppliedVelocity.AsVector));
  NewtonBodyGetOmega(cbody, @(FAppliedOmega.AsVector));

  // Raise Custom event
  if Assigned(FCustomForceAndTorqueEvent) then
    FCustomForceAndTorqueEvent(cbody, timestep, threadIndex)
  else
  begin
    NewtonBodySetForce(cbody, @(Force.AsVector));
    NewtonBodySetTorque(cbody, @(Torque.AsVector));

    // Add Gravity from World
    if FUseGravity then
    begin
      worldGravity := VectorScale(FManager.Gravity.AsVector, FMass);
      NewtonBodyAddForce(cbody, @(worldGravity));
    end;
  end;

end;

procedure TgxNGDDynamic.OnSetTransformEvent(const cbody: PNewtonBody;
  const cmatrix: PNGDFloat; threadIndex: Integer);
var
  epsi: Single;
begin
  // The Newton API does not support scale [scale modifie value in matrix],
  // so this line reset scale of the GXSceneObject to (1,1,1)
  // to avoid crashing the application
  epsi := 0.0001;
  with FOwnerBaseSceneObject do
    if not SameValue(Scale.X, 1.0, epsi) or not SameValue(Scale.Y, 1.0, epsi)
      or not SameValue(Scale.Z, 1.0, epsi) then
    begin
      Scale.SetVector(1, 1, 1);
      SetNewtonBodyMatrix(AbsoluteMatrix);
    end
    else
      // Make the Position and orientation of the glscene-Object relative to the
      // NewtonBody position and orientation.
      FOwnerBaseSceneObject.AbsoluteMatrix := pMatrix(cmatrix)^;
end;

// ------------------------------------------------------------------
{ TgxNGDStatic }
// ------------------------------------------------------------------
procedure TgxNGDStatic.Render;
begin
  inherited;
  // Move/Rotate NewtonObject if matrix are not equal in run time.
  if not MatrixEquals(NewtonBodyMatrix, FOwnerBaseSceneObject.AbsoluteMatrix)
    then
    SetNewtonBodyMatrix(FOwnerBaseSceneObject.AbsoluteMatrix);

end;

class function TgxNGDStatic.FriendlyName: string;
begin
  Result := 'NGD Static';
end;

// ------------------------------------------------------------------
{ TNGDSurfaceItem }
// ------------------------------------------------------------------
function TNGDSurfaceItem.GetDisplayName: string;
begin
  if FDisplayName = '' then
    FDisplayName := 'Iron';
  Result := FDisplayName;
end;

procedure TNGDSurfaceItem.SetDisplayName(const Value: string);
begin
  inherited;
  FDisplayName := Value;
end;

{ TNGDSurfacePair }

constructor TNGDSurfacePair.Create(Collection: TCollection);
begin
  inherited;
  FSoftness := 0.1;
  FElasticity := 0.4;
  FCollidable := True;
  FStaticFriction := 0.9;
  FKineticFriction := 0.5;
  FContinuousCollisionMode := False;
  FThickness := False;

  FAABBOverlapEvent := OnNewtonAABBOverlapEvent;
  FContactProcessEvent := OnNewtonContactsProcessEvent;
  FManager := TgxNGDManager(Collection.Owner);
  FManager.RebuildAllMaterial;
end;

class function TNGDSurfacePair.NewtonAABBOverlap
  (const material: PNewtonMaterial;
  const body0, body1: PNewtonBody; threadIndex: Integer): Integer; cdecl;
begin
  Result := Ord(TNGDSurfacePair(NewtonMaterialGetMaterialPairUserData(material))
      .FAABBOverlapEvent(material, body0, body1, threadIndex));
end;

class procedure TNGDSurfacePair.NewtonContactsProcess
  (const contact: PNewtonJoint; timestep: NGDFloat; threadIndex: Integer); cdecl;
begin
  TNGDSurfacePair(NewtonMaterialGetMaterialPairUserData
   (NewtonContactGetMaterial
     (NewtonContactJointGetFirstContact(contact)))).FContactProcessEvent
	    (contact, timestep, threadIndex);
end;

function TNGDSurfacePair.OnNewtonAABBOverlapEvent
  (const cmaterial: PNewtonMaterial; const cbody0, cbody1: PNewtonBody;
  threadIndex: Integer): Boolean;
begin
  Result := True;
end;

procedure TNGDSurfacePair.OnNewtonContactsProcessEvent
  (const ccontact: PNewtonJoint; timestep: NGDFloat; threadIndex: Integer);
begin

end;

procedure TNGDSurfacePair.SetCollidable(const Value: Boolean);
begin
  FCollidable := Value;
  FManager.RebuildAllMaterial;
end;

procedure TNGDSurfacePair.SetContinuousCollisionMode(const Value: Boolean);
begin
  FContinuousCollisionMode := Value;
  FManager.RebuildAllMaterial;
end;

procedure TNGDSurfacePair.SetElasticity(const Value: Single);
begin
  if (Value >= 0) then
    FElasticity := Value;
  FManager.RebuildAllMaterial;
end;

procedure TNGDSurfacePair.SetKineticFriction(const Value: Single);
begin
  if (Value >= 0) and (Value <= 1) then
    FKineticFriction := Value;
  FManager.RebuildAllMaterial;
end;

procedure TNGDSurfacePair.SetMaterialItems(const item1, item2: TNGDSurfaceItem);
begin
  FNGDSurfaceItem1 := item1;
  FNGDSurfaceItem2 := item2;
  FManager.RebuildAllMaterial;
end;

procedure TNGDSurfacePair.SetSoftness(const Value: Single);
begin
  if (Value >= 0) and (Value <= 1) then
    FSoftness := Value;
  FManager.RebuildAllMaterial;
end;

procedure TNGDSurfacePair.SetStaticFriction(const Value: Single);
begin
  if (Value >= 0) and (Value <= 1) then
    FStaticFriction := Value;
  FManager.RebuildAllMaterial;
end;

procedure TNGDSurfacePair.SetThickness(const Value: Boolean);
begin
  FThickness := Value;
  FManager.RebuildAllMaterial;
end;

function TNGDSurfacePair.StoredElasticity: Boolean;
begin
  Result := not SameValue(FElasticity, 0.4, epsilon);
end;

function TNGDSurfacePair.StoredKineticFriction: Boolean;
begin
  Result := not SameValue(FKineticFriction, 0.5, epsilon);
end;

function TNGDSurfacePair.StoredSoftness: Boolean;
begin
  Result := not SameValue(FSoftness, 0.1, epsilon);
end;

function TNGDSurfacePair.StoredStaticFriction: Boolean;
begin
  Result := not SameValue(FStaticFriction, 0.9, epsilon);
end;

{ TNGDJoint }

constructor TNGDJoint.Create(Collection: TCollection);
begin
  inherited;
  FCollisionState := False;
  FStiffness := 0.9;
  FNewtonJoint := nil;
  FNewtonUserJoint := nil;
  FParentObject := nil;
  FChildObject := nil;

  FManager := TgxNGDManager(Collection.Owner);

  FBallAndSocketOptions := TNGDJointPivot.Create(FManager, self);
  FHingeOptions := TNGDJointPin.Create(FManager, self);
  FSliderOptions := TNGDJointPin.Create(FManager, self);
  FCorkscrewOptions := TNGDJointPin.Create(FManager, self);
  FUniversalOptions := TNGDJointPin2.Create(FManager, self);

  FCustomBallAndSocketOptions := TNGDJointBallAndSocket.Create(FManager, self);
  FCustomHingeOptions := TNGDJointHinge.Create(FManager, self);
  FCustomSliderOptions := TNGDJointSlider.Create(FManager, self);
  FKinematicOptions := TNGDJointKinematicController.Create;

  FUPVectorDirection := TgxCoordinates.CreateInitialized(self, YHmgVector,
    csVector);
  FUPVectorDirection.OnNotifyChange := FManager.RebuildAllJoint;
end;

destructor TNGDJoint.Destroy;
begin
  DestroyNewtonData;

  FParentObject := nil;
  FChildObject := nil;

  // Free options
  FBallAndSocketOptions.Free;
  FHingeOptions.Free;
  FSliderOptions.Free;
  FCorkscrewOptions.Free;
  FUniversalOptions.Free;

  FCustomBallAndSocketOptions.Free;
  FCustomHingeOptions.Free;
  FCustomSliderOptions.Free;
  FKinematicOptions.Free;
  FUPVectorDirection.Free;
  inherited;
end;

procedure TNGDJoint.DestroyNewtonData;
begin
  if FNewtonJoint <> nil then
  begin
    Assert((FManager <> nil) and (FManager.FNewtonWorld <> nil));
    NewtonDestroyJoint(FManager.FNewtonWorld, FNewtonJoint);
    FNewtonJoint := nil;
  end;
  if FNewtonUserJoint <> nil then
  begin
    CustomDestroyJoint(FNewtonUserJoint);
    FNewtonUserJoint := nil;
  end;
end;

procedure TNGDJoint.KinematicControllerPick(pickpoint: TVector;
  PickedActions: TNGDPickedActions);
begin
  if FJointType = nj_KinematicController then
    if Assigned(FParentObject) then
    begin
      // Create the joint
      if PickedActions = paAttach then
      begin
        if not Assigned(FNewtonUserJoint) then
          if Assigned(GetNGDDynamic(FParentObject).FNewtonBody) then
            FNewtonUserJoint := CreateCustomKinematicController
              (GetNGDDynamic(FParentObject).FNewtonBody, @pickpoint);
      end;

      // Change the TargetPoint
      if (PickedActions = paMove) or (PickedActions = paAttach) then
      begin
        if Assigned(FNewtonUserJoint) then
        begin
          CustomKinematicControllerSetPickMode(FNewtonUserJoint,
            Ord(FKinematicOptions.FPickModeLinear));
          CustomKinematicControllerSetMaxLinearFriction(FNewtonUserJoint,
            FKinematicOptions.FLinearFriction);
          CustomKinematicControllerSetMaxAngularFriction(FNewtonUserJoint,
            FKinematicOptions.FAngularFriction);
          CustomKinematicControllerSetTargetPosit(FNewtonUserJoint, @pickpoint);
        end;
      end;

      // Delete the joint
      if PickedActions = paDetach then
      begin
        if Assigned(FNewtonUserJoint) then
        begin
          CustomDestroyJoint(FNewtonUserJoint);
          FNewtonUserJoint := nil;
          // Reset autosleep because this joint turns it off
          NewtonBodySetAutoSleep(GetNGDDynamic(FParentObject).FNewtonBody,
            Ord(GetNGDDynamic(FParentObject).AutoSleep));
        end;
        ParentObject := nil;
      end;
    end;
end;

procedure TNGDJoint.Render;

  procedure DrawPivot(pivot: TVector);
  var
    size: Single;
  begin
    size := FManager.DebugOption.DotAxisSize;
    FManager.FCurrentColor := FManager.DebugOption.JointPivotColor;
    FManager.AddNode(VectorAdd(pivot, VectorMake(0, 0, size)));
    FManager.AddNode(VectorAdd(pivot, VectorMake(0, 0, -size)));
    FManager.AddNode(VectorAdd(pivot, VectorMake(0, size, 0)));
    FManager.AddNode(VectorAdd(pivot, VectorMake(0, -size, 0)));
    FManager.AddNode(VectorAdd(pivot, VectorMake(size, 0, 0)));
    FManager.AddNode(VectorAdd(pivot, VectorMake(-size, 0, 0)));
  end;

  procedure DrawPin(pin, pivot: TVector);
  begin
    FManager.FCurrentColor := FManager.DebugOption.JointAxisColor;
    FManager.AddNode(VectorAdd(pivot, pin));
    FManager.AddNode(VectorAdd(pivot, VectorNegate(pin)));
  end;

  procedure DrawJoint(pivot: TVector);
  begin
    FManager.FCurrentColor := FManager.DebugOption.CustomColor;
    FManager.AddNode(FParentObject.AbsolutePosition);
    FManager.AddNode(pivot);
    FManager.AddNode(pivot);
    FManager.AddNode(FChildObject.AbsolutePosition);
  end;

  procedure DrawKinematic;
  var
    pickedMatrix: TMatrix;
    size: Single;
  begin
    size := FManager.DebugOption.DotAxisSize;
    CustomKinematicControllerGetTargetMatrix(FNewtonUserJoint, @pickedMatrix);
    FManager.FCurrentColor := FManager.DebugOption.JointAxisColor;

    FManager.AddNode(FParentObject.AbsolutePosition);
    FManager.AddNode(pickedMatrix.W);

    FManager.FCurrentColor := FManager.DebugOption.JointPivotColor;
    FManager.AddNode(VectorAdd(pickedMatrix.W, VectorMake(0, 0, size)));
    FManager.AddNode(VectorAdd(pickedMatrix.W, VectorMake(0, 0, -size)));
    FManager.AddNode(VectorAdd(pickedMatrix.W, VectorMake(0, size, 0)));
    FManager.AddNode(VectorAdd(pickedMatrix.W, VectorMake(0, -size, 0)));
    FManager.AddNode(VectorAdd(pickedMatrix.W, VectorMake(size, 0, 0)));
    FManager.AddNode(VectorAdd(pickedMatrix.W, VectorMake(-size, 0, 0)));
  end;

begin

  case FJointType of
    nj_BallAndSocket:
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        DrawJoint(FBallAndSocketOptions.FPivotPoint.AsVector);
        DrawPivot(FBallAndSocketOptions.FPivotPoint.AsVector);
      end;

    nj_Hinge:
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        DrawJoint(FHingeOptions.FPivotPoint.AsVector);
        DrawPin(FHingeOptions.FPinDirection.AsVector,
          FHingeOptions.FPivotPoint.AsVector);
        DrawPivot(FHingeOptions.FPivotPoint.AsVector);
      end;

    nj_Slider:
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        DrawJoint(FSliderOptions.FPivotPoint.AsVector);
        DrawPin(FSliderOptions.FPinDirection.AsVector,
          FSliderOptions.FPivotPoint.AsVector);
        DrawPivot(FSliderOptions.FPivotPoint.AsVector);
      end;

    nj_Corkscrew:
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        DrawJoint(FCorkscrewOptions.FPivotPoint.AsVector);
        DrawPin(FCorkscrewOptions.FPinDirection.AsVector,
          FCorkscrewOptions.FPivotPoint.AsVector);
        DrawPivot(FCorkscrewOptions.FPivotPoint.AsVector);
      end;

    nj_Universal:
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        DrawJoint(FUniversalOptions.FPivotPoint.AsVector);
        DrawPin(FUniversalOptions.FPinDirection.AsVector,
          FUniversalOptions.FPivotPoint.AsVector);
        DrawPin(FUniversalOptions.FPinDirection2.AsVector,
          FUniversalOptions.FPivotPoint.AsVector);
        DrawPivot(FUniversalOptions.FPivotPoint.AsVector);
      end;

    nj_CustomBallAndSocket:
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        DrawJoint(FCustomBallAndSocketOptions.FPivotPoint.AsVector);
        DrawPivot(FCustomBallAndSocketOptions.FPivotPoint.AsVector);
      end;

    nj_CustomHinge:
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        DrawJoint(FCustomHingeOptions.FPivotPoint.AsVector);
        DrawPin(FCustomHingeOptions.FPinDirection.AsVector,
          FCustomHingeOptions.FPivotPoint.AsVector);
        DrawPivot(FCustomHingeOptions.FPivotPoint.AsVector);
      end;

    nj_CustomSlider:
      if Assigned(FParentObject) and Assigned(FChildObject) then
      begin
        DrawJoint(FCustomSliderOptions.FPivotPoint.AsVector);
        DrawPin(FCustomSliderOptions.FPinDirection.AsVector,
          FCustomSliderOptions.FPivotPoint.AsVector);
        DrawPivot(FCustomSliderOptions.FPivotPoint.AsVector);
      end;

    nj_UpVector:
      if Assigned(FParentObject) then
      begin // special
        FManager.FCurrentColor := FManager.DebugOption.JointAxisColor;
        FManager.AddNode(FParentObject.AbsolutePosition);
        FManager.AddNode(VectorAdd(FParentObject.AbsolutePosition,
            FUPVectorDirection.AsVector));
      end;

    nj_KinematicController:
      if Assigned(FParentObject) and Assigned(FNewtonUserJoint) then
      begin // special
        DrawKinematic;
      end;

  end;
end;

procedure TNGDJoint.SetChildObject(const Value: TgxBaseSceneObject);
begin
  FChildObject := Value;
  FManager.RebuildAllJoint(self);
end;

procedure TNGDJoint.SetCollisionState(const Value: Boolean);
begin
  FCollisionState := Value;
  FManager.RebuildAllJoint(self);
end;

procedure TNGDJoint.SetJointType(const Value: TNGDNewtonJoints);
begin
  FJointType := Value;
  FManager.RebuildAllJoint(self);
end;

procedure TNGDJoint.SetParentObject(const Value: TgxBaseSceneObject);
begin
  FParentObject := Value;
  FManager.RebuildAllJoint(self);
end;

procedure TNGDJoint.SetStiffness(const Value: Single);
begin
  if (Value >= 0) and (Value <= 1) then
  begin
    FStiffness := Value;
    FManager.RebuildAllJoint(self);
  end;
end;

function TNGDJoint.StoredStiffness: Boolean;
begin
  Result := not SameValue(FStiffness, 0.9, epsilon);
end;

// ------------------------------------------------------------------
{ TNGDJoint.TNGDJointPivot }
// ------------------------------------------------------------------
constructor TNGDJointPivot.Create(AOwner: TComponent; aOuter: TNGDJoint);
begin
  FManager := AOwner as TgxNGDManager;
  FOuter := aOuter;
  FPivotPoint := TgxCoordinates.CreateInitialized(aOuter, NullHMGPoint,
    csPoint);
  FPivotPoint.OnNotifyChange := FManager.RebuildAllJoint;
end;

destructor TNGDJointPivot.Destroy;
begin
  FPivotPoint.Free;
  inherited;
end;

// ------------------------------------------------------------------
{ TNGDJoint.TNGDJointPin }
// ------------------------------------------------------------------
constructor TNGDJointPin.Create(AOwner: TComponent; aOuter: TNGDJoint);
begin
  inherited;
  FPinDirection := TgxCoordinates.CreateInitialized(aOuter, NullHmgVector,
    csVector);
  FPinDirection.OnNotifyChange := FManager.RebuildAllJoint;
end;

destructor TNGDJointPin.Destroy;
begin
  FPinDirection.Free;
  inherited;
end;

// ------------------------------------------------------------------
{ TNGDJoint.TNGDJointPin2 }
// ------------------------------------------------------------------
constructor TNGDJointPin2.Create(AOwner: TComponent; aOuter: TNGDJoint);
begin
  inherited;
  FPinDirection2 := TgxCoordinates.CreateInitialized(aOuter, NullHmgVector,
    csVector);
  FPinDirection2.OnNotifyChange := FManager.RebuildAllJoint;
end;

destructor TNGDJointPin2.Destroy;
begin
  FPinDirection2.Free;
  inherited;
end;

// ------------------------------------------------------------------
{ TNGDJoint.TNGDJointBallAndSocket }
// ------------------------------------------------------------------
constructor TNGDJointBallAndSocket.Create(AOwner: TComponent;
  aOuter: TNGDJoint);
begin
  inherited;
  FConeAngle := 90;
  FMinTwistAngle := -90;
  FMaxTwistAngle := 90;
end;

procedure TNGDJointBallAndSocket.SetConeAngle(const Value: Single);
begin
  FConeAngle := Value;
  FManager.RebuildAllJoint(FOuter);
end;

procedure TNGDJointBallAndSocket.SetMaxTwistAngle(const Value: Single);
begin
  FMaxTwistAngle := Value;
  FManager.RebuildAllJoint(FOuter);
end;

procedure TNGDJointBallAndSocket.SetMinTwistAngle(const Value: Single);
begin
  FMinTwistAngle := Value;
  FManager.RebuildAllJoint(FOuter);
end;

function TNGDJointBallAndSocket.StoredConeAngle: Boolean;
begin
  Result := not SameValue(FConeAngle, 90, epsilon);
end;

function TNGDJointBallAndSocket.StoredMaxTwistAngle: Boolean;
begin
  Result := not SameValue(FMaxTwistAngle, 90, epsilon);
end;

function TNGDJointBallAndSocket.StoredMinTwistAngle: Boolean;
begin
  Result := not SameValue(FMinTwistAngle, -90, epsilon);
end;

// ------------------------------------------------------------------
{ TNGDJoint.TNGDJointHinge }
// ------------------------------------------------------------------
constructor TNGDJointHinge.Create(AOwner: TComponent; aOuter: TNGDJoint);
begin
  inherited;
  FMinAngle := -90;
  FMaxAngle := 90;
end;

procedure TNGDJointHinge.SetMaxAngle(const Value: Single);
begin
  FMaxAngle := Value;
  FManager.RebuildAllJoint(FOuter);
end;

procedure TNGDJointHinge.SetMinAngle(const Value: Single);
begin
  FMinAngle := Value;
  FManager.RebuildAllJoint(FOuter);
end;

function TNGDJointHinge.StoredMaxAngle: Boolean;
begin
  Result := not SameValue(FMaxAngle, 90, epsilon);
end;

function TNGDJointHinge.StoredMinAngle: Boolean;
begin
  Result := not SameValue(FMinAngle, -90, epsilon);
end;

// ------------------------------------------------------------------
{ TNGDJoint.TNGDJointSlider }
// ------------------------------------------------------------------
constructor TNGDJointSlider.Create(AOwner: TComponent; aOuter: TNGDJoint);
begin
  inherited;
  FMinDistance := -10;
  FMaxDistance := 10;
end;


procedure TNGDJointSlider.SetMaxDistance(const Value: Single);
begin
  FMaxDistance := Value;
  FManager.RebuildAllJoint(FOuter);
end;

procedure TNGDJointSlider.SetMinDistance(const Value: Single);
begin
  FMinDistance := Value;
  FManager.RebuildAllJoint(FOuter);
end;


function TNGDJointSlider.StoredMaxDistance: Boolean;
begin
  Result := not SameValue(FMaxDistance, 10, epsilon);
end;

function TNGDJointSlider.StoredMinDistance: Boolean;
begin
  Result := not SameValue(FMinDistance, -10, epsilon);
end;

{ TNGDJoint.TNGDJointKinematicController }

constructor TNGDJointKinematicController.Create;
begin
  FPickModeLinear := False;
  FLinearFriction := 750;
  FAngularFriction := 250;
end;

function TNGDJointKinematicController.StoredAngularFriction: Boolean;
begin
  Result := not SameValue(FAngularFriction, 250, epsilon);
end;

function TNGDJointKinematicController.StoredLinearFriction: Boolean;
begin
  Result := not SameValue(FLinearFriction, 750, epsilon);
end;

// ------------------------------------------------------------------
{ TgxNGDBehaviourList }
// ------------------------------------------------------------------
function TgxNGDBehaviourList.GetBehav(index: Integer): TgxNGDBehaviour;
begin
  Result := Items[index];
end;

procedure TgxNGDBehaviourList.PutBehav(index: Integer; Item: TgxNGDBehaviour);
begin
  inherited put(index, Item);
end;

initialization

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

RegisterXCollectionItemClass(TgxNGDDynamic);
RegisterXCollectionItemClass(TgxNGDStatic);

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

finalization

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

UnregisterXCollectionItemClass(TgxNGDDynamic);
UnregisterXCollectionItemClass(TgxNGDStatic);

// CloseNGD;

end.
