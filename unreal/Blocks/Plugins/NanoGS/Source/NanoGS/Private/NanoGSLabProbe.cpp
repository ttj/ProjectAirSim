// Runtime probe: spawn a Gaussian splat asset + a posed camera from the console.
// Added for headless verification on Linux/Vulkan (not part of upstream NanoGS).
#include "CoreMinimal.h"
#include "Engine/World.h"
#include "Engine/Engine.h"
#include "HAL/IConsoleManager.h"
#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "GameFramework/PlayerController.h"
#include "GaussianSplatActor.h"
#include "GaussianSplatComponent.h"
#include "GaussianSplatAsset.h"
#include "Containers/Ticker.h"
#include "UnrealClient.h"
#include "Misc/CoreDelegates.h"

static void NanoGSSpawnLab(const TArray<FString>& Args, UWorld* World, FOutputDevice& Ar)
{
	if (!World) { Ar.Logf(TEXT("NANOGS_PROBE: no world")); return; }

	const FString AssetPath = Args.IsValidIndex(0) ? Args[0] : TEXT("/Game/NanoGS/LabV6.LabV6");
	auto Num = [&](int32 i, float d) { return Args.IsValidIndex(i) ? FCString::Atof(*Args[i]) : d; };
	const FVector  Eye(Num(1, 520.f), Num(2, 60.f), Num(3, 120.f));
	const FRotator Rot(Num(4, 0.f), Num(5, -84.544f), 0.f);   // (Pitch, Yaw, Roll)
	const float    Fov = Num(6, 73.622f);

	UGaussianSplatAsset* Asset = LoadObject<UGaussianSplatAsset>(nullptr, *AssetPath);
	Ar.Logf(TEXT("NANOGS_PROBE: asset %s -> %s"), *AssetPath, Asset ? TEXT("LOADED") : TEXT("NULL"));
	if (!Asset) { return; }
	Ar.Logf(TEXT("NANOGS_PROBE: splats=%d valid=%d"), Asset->GetSplatCount(), Asset->IsValid() ? 1 : 0);

	FActorSpawnParameters P; P.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	AGaussianSplatActor* SplatActor = World->SpawnActor<AGaussianSplatActor>(
		AGaussianSplatActor::StaticClass(), FVector::ZeroVector, FRotator::ZeroRotator, P);
	if (!SplatActor) { Ar.Logf(TEXT("NANOGS_PROBE: spawn FAILED")); return; }
	SplatActor->SetActorScale3D(FVector(1.f));
	if (UGaussianSplatComponent* C = SplatActor->GaussianSplatComponent)
	{
		C->SetSplatAsset(Asset);
		Ar.Logf(TEXT("NANOGS_PROBE: component splats=%d"), C->GetSplatCount());
	}
	const FBox B = SplatActor->GetComponentsBoundingBox(true);
	Ar.Logf(TEXT("NANOGS_PROBE: bounds min=(%.1f,%.1f,%.1f) max=(%.1f,%.1f,%.1f) cm"),
		B.Min.X, B.Min.Y, B.Min.Z, B.Max.X, B.Max.Y, B.Max.Z);

	ACameraActor* Cam = World->SpawnActor<ACameraActor>(ACameraActor::StaticClass(), Eye, Rot, P);
	if (Cam)
	{
		Cam->GetCameraComponent()->SetFieldOfView(Fov);
		Cam->GetCameraComponent()->SetConstraintAspectRatio(false);   // no 16:9 letterbox
		Cam->GetCameraComponent()->SetAspectRatio(4.0f / 3.0f);
		if (APlayerController* PC = World->GetFirstPlayerController())
		{
			PC->SetViewTarget(Cam);
			Ar.Logf(TEXT("NANOGS_PROBE: view target set, eye=(%.1f,%.1f,%.1f) pitch=%.3f yaw=%.3f fov=%.3f"),
				Eye.X, Eye.Y, Eye.Z, Rot.Pitch, Rot.Yaw, Fov);
		}
		else { Ar.Logf(TEXT("NANOGS_PROBE: NO PLAYER CONTROLLER")); }
	}
	Ar.Logf(TEXT("NANOGS_PROBE: DONE"));
}

static FAutoConsoleCommandWithWorldArgsAndOutputDevice GNanoGSSpawnLabCmd(
	TEXT("NanoGS.SpawnLab"),
	TEXT("NanoGS.SpawnLab [AssetPath] [X Y Z] [Pitch Yaw] [FOV] - spawn splat + posed camera"),
	FConsoleCommandWithWorldArgsAndOutputDeviceDelegate::CreateStatic(&NanoGSSpawnLab));

// Delayed screenshot: let the splat's GPU resources settle, capture, then exit.
static void NanoGSShot(const TArray<FString>& Args, UWorld* World, FOutputDevice& Ar)
{
	const float Delay = Args.IsValidIndex(0) ? FCString::Atof(*Args[0]) : 5.0f;
	const FString Name = Args.IsValidIndex(1) ? Args[1] : TEXT("/tmp/claude-1001/nanogs/frame.png");
	Ar.Logf(TEXT("NANOGS_PROBE: shot scheduled in %.1fs -> %s"), Delay, *Name);
	TSharedPtr<float> Acc = MakeShared<float>(0.f);
	TSharedPtr<int32> Phase = MakeShared<int32>(0);
	FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda(
		[Acc, Phase, Delay, Name](float Dt) -> bool
		{
			*Acc += Dt;
			if (*Phase == 0 && *Acc >= Delay)
			{
				FScreenshotRequest::RequestScreenshot(Name, false, false);
				UE_LOG(LogTemp, Display, TEXT("NANOGS_PROBE: screenshot requested -> %s"), *Name);
				*Phase = 1; *Acc = 0.f;
				return true;
			}
			if (*Phase == 1 && *Acc >= 3.0f)
			{
				UE_LOG(LogTemp, Display, TEXT("NANOGS_PROBE: exiting"));
				FGenericPlatformMisc::RequestExit(false);
				return false;
			}
			return true;
		}), 0.f);
}

static FAutoConsoleCommandWithWorldArgsAndOutputDevice GNanoGSShotCmd(
	TEXT("NanoGS.Shot"),
	TEXT("NanoGS.Shot [delaySeconds] [absolutePath.png] - capture then exit"),
	FConsoleCommandWithWorldArgsAndOutputDeviceDelegate::CreateStatic(&NanoGSShot));
