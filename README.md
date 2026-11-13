# Scene VRM

VRM avatar loader for [Flutter Scene](https://fscene.dev).  
Supports loading VRM(0.x/1.x) and VRMA animations.

⚠️ Development Status. 

This project is currently in an early stage of development.  
There are still many TODOs.  
Breaking changes may occur without prior notice.

```
import 'package:flutter_scene/scene.dart';
import 'package:scene_vrm/scene_vrm.dart';

final scene = Scene();

// Load a vrm avatar from bytes.
final node = await loadVrmBytes(vrmBytes);

scene.add(node);

// Retrieve a VRM component.
final vrm = node.getComponent<Vrm>();

// Load a vrma animation from bytes;
final animation = VrmAnimation.fromBytes(vrmaBytes);

final clip = vrm?.createAnimationClip(animation);

// Play an animation;
clip?.play();
```
