extends SceneTree
func _initialize() -> void:
 var basis := Basis(Vector3.FORWARD,PI*.5)
 var expected := Transform3D(basis*Basis.from_scale(Vector3(.15,.08,.15)),Vector3(-7.75,12.7136363983154,1.98802673816681))
 var multiplied := Transform3D.IDENTITY*expected
 var stored := Transform3D(expected.basis,expected.origin)
 print('EXPECTED ',expected)
 print('AFTER_IDENTITY ',multiplied)
 print('BASIS_Y_Z keys ', '%.3f'%expected.basis.y.z,' / ','%.3f'%multiplied.basis.y.z)
 print('MATRIX_EXPECTED ',_key(expected))
 print('MATRIX_IDENTITY ',_key(multiplied))
 print('MATRIX_STORED ',_key(stored))
 quit()
func _key(t:Transform3D)->String:
 return '%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f'%[t.origin.x,t.origin.y,t.origin.z,t.basis.x.x,t.basis.x.y,t.basis.x.z,t.basis.y.x,t.basis.y.y,t.basis.y.z,t.basis.z.x,t.basis.z.y,t.basis.z.z]
