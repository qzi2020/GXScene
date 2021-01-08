 //
 // The graphics rendering engine GXScene  http://glscene.org
 //
unit GXS.FileMD3;

(* Code for loading animated MD3 files into GXScene FreeForms and Actors *)

interface

uses
  System.Classes,
  System.SysUtils,

  GXS.ApplicationFileIO,
  GXS.VectorGeometry,
  GXS.VectorFileObjects,
  GXS.Material,
  GXS.Texture,

  Formatx.MD3;

type

  TgxMD3VectorFile = class (TgxVectorFile)
    public
      class function Capabilities : TgxDataFileCapabilities; override;
      procedure LoadFromStream(aStream : TStream); override;
  end;

//==================================================================
implementation
//==================================================================

// ------------------
// ------------------ TgxMD3VectorFile ------------------
// ------------------

class function TgxMD3VectorFile.Capabilities : TgxDataFileCapabilities;
begin
  Result:=[dfcRead];
end;

procedure TgxMD3VectorFile.LoadFromStream(aStream : TStream);
var
  i,j,k,
  numVerts,
  numtris     : Integer;
  MD3File     : TFileMD3;
  mesh        : TgxMorphableMeshObject;
  faceGroup   : TFGIndexTexCoordList;
  morphTarget : TgxMeshMorphTarget;

  function GetNormalFromMD3Normal(n : array of Byte) : TAffineVector;
  var
    lat,lng : single;
  begin
    // The MD3 normal is a latitude/longitude value that needs
    // to be calculated into cartesian space.
    lat:=(n[1])*(2*pi)/255; lng:=(n[0])*(2*pi)/255;
    result.X:=cos(lat)*sin(lng);
    result.Y:=sin(lat)*sin(lng);
    result.Z:=cos(lng);
  end;

  procedure AllocateMaterial(meshname:string);
  var
    LibMat : TgxLibMaterial;
  begin
    // If a material library is assigned to the actor/freeform the
    // mesh name will be added as a material.
    if Assigned(Owner.MaterialLibrary) then with Owner.MaterialLibrary do begin
      if Assigned(Materials.GetLibMaterialByName(meshname)) then exit;
      LibMat:=Materials.Add;
      LibMat.name:=meshname;
      LibMat.Material.Texture.Disabled:=False;
    end;
  end;

begin
  MD3File:=TFileMD3.Create;
  MD3File.LoadFromStream(aStream);
  try
    for i:=0 to MD3File.ModelHeader.numMeshes-1 do begin
      mesh:=TgxMorphableMeshObject.CreateOwned(Owner.MeshObjects);
      mesh.Name:=trim(string(MD3File.MeshData[i].MeshHeader.strName));
      with mesh, MD3File do begin
        Mode:=momFaceGroups;
        faceGroup:=TFGIndexTexCoordList.CreateOwned(FaceGroups);
        with faceGroup do begin
          AllocateMaterial(mesh.Name);
          MaterialName:=mesh.Name;
          numTris:=MeshData[i].MeshHeader.numTriangles;
          VertexIndices.Capacity:=numTris*3;
          TexCoords.Capacity:=numTris*3;
          // Get the vertex indices and texture coordinates
          for j:=0 to MeshData[i].MeshHeader.numTriangles-1 do begin
            with MeshData[i].Triangles[j] do begin
              Add(vertexIndices.X,
                  MeshData[i].TexCoords[vertexIndices.X].textureCoord.X,
                  1-MeshData[i].TexCoords[vertexIndices.X].textureCoord.Y);
              Add(vertexIndices.Z,
                  MeshData[i].TexCoords[vertexIndices.Z].textureCoord.X,
                  1-MeshData[i].TexCoords[vertexIndices.Z].textureCoord.Y);
              Add(vertexIndices.Y,
                  MeshData[i].TexCoords[vertexIndices.Y].textureCoord.X,
                  1-MeshData[i].TexCoords[vertexIndices.Y].textureCoord.Y);
            end;
          end;
        end;

        // Get the mesh data for each morph frame
        for j:=0 to ModelHeader.numFrames-1 do begin
          morphTarget:=TgxMeshMorphTarget.CreateOwned(MorphTargets);
          morphTarget.Name:=Trim(string(MeshData[i].MeshHeader.strName))+'['+IntToStr(j)+']';
          numVerts:=MeshData[i].MeshHeader.numVertices;
          morphTarget.Vertices.Capacity:=numVerts;
          for k:=numVerts*j to numVerts*(j+1)-1 do begin
            morphTarget.Vertices.Add(
              MeshData[i].Vertices[k].Vertex.X/64,
              MeshData[i].Vertices[k].Vertex.Y/64,
              MeshData[i].Vertices[k].Vertex.Z/64);
            morphTarget.Normals.Add(
              GetNormalFromMD3Normal(MeshData[i].Vertices[k].normal.V));
          end;
        end;

      end;
      if mesh.MorphTargets.Count>0 then
        mesh.MorphTo(0);
    end;
  finally
    MD3File.Free;
  end;
end;

// ------------------------------------------------------------------
initialization
// ------------------------------------------------------------------

   RegisterVectorFileFormat('md3', 'MD3 files', TgxMD3VectorFile);

end.
